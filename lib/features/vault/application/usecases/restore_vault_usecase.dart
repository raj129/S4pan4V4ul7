import 'dart:convert';

import 'package:photo_vault/core/crypto/models/wrapped_key.dart';
import 'package:photo_vault/core/crypto/services/crypto_service.dart';
import 'package:photo_vault/core/session/vault_session.dart';

import '../../domain/entities/user_mode.dart';
import '../../domain/entities/vault_settings.dart';
import '../../domain/repositories/secure_storage_repository.dart';
import '../../domain/repositories/vault_repository.dart';
import '../../domain/repositories/vmk_backup_repository.dart';
import '../services/kdf_service.dart';

class RestoreVaultException implements Exception {
  const RestoreVaultException(this.message);

  final String message;

  @override
  String toString() => message;
}

class VaultBackupNotFoundException extends RestoreVaultException {
  const VaultBackupNotFoundException()
    : super('No backup was found for this vault.');
}

class VaultBackupLookupException extends RestoreVaultException {
  const VaultBackupLookupException(super.message);
}

class VaultBackupPinException extends RestoreVaultException {
  const VaultBackupPinException()
    : super(
        'The original PIN could not open this backup. Check the PIN or backup data.',
      );
}

class VaultBackupFormatException extends RestoreVaultException {
  const VaultBackupFormatException()
    : super('The vault backup is incomplete or has an unsupported format.');
}

/// Restores a Drive-wrapped VMK locally without generating a new vault identity.
class RestoreVaultUseCase {
  RestoreVaultUseCase({
    required CryptoService cryptoService,
    required KdfService kdfService,
    required VaultRepository vaultRepository,
    required SecureStorageRepository secureStorageRepository,
    required VaultSession vaultSession,
    required List<VmkBackupRepository> backupRepositories,
  }) : _cryptoService = cryptoService,
       _kdfService = kdfService,
       _vaultRepository = vaultRepository,
       _secureStorageRepository = secureStorageRepository,
       _vaultSession = vaultSession,
       _backupRepositories = backupRepositories;

  final CryptoService _cryptoService;
  final KdfService _kdfService;
  final VaultRepository _vaultRepository;
  final SecureStorageRepository _secureStorageRepository;
  final VaultSession _vaultSession;
  final List<VmkBackupRepository> _backupRepositories;

  Future<List<String>> listVaultIds({bool interactive = true}) async {
    final ids = <String>{};
    final failures = <String>[];
    for (final repository in _backupRepositories) {
      try {
        ids.addAll(await repository.listVaultIds(interactive: interactive));
      } catch (error) {
        failures.add('${repository.runtimeType}: $error');
      }
    }
    final hasInvalidId = ids.any((id) => !_isVaultId(id));
    ids.removeWhere((id) => !_isVaultId(id));
    if (ids.isEmpty && hasInvalidId) {
      throw const VaultBackupFormatException();
    }
    if (ids.isEmpty && failures.isNotEmpty) {
      throw VaultBackupLookupException(
        'Could not check Google vault backups: ${failures.join('; ')}',
      );
    }
    if (ids.isEmpty) return const [];
    return ids.toList()..sort();
  }

  Future<void> execute({
    required String vaultId,
    required String originalPin,
    required String newPin,
  }) async {
    if (!_isVaultId(vaultId)) {
      throw const VaultBackupFormatException();
    }
    if (!_isPin(originalPin) || !_isPin(newPin)) {
      throw const RestoreVaultException('Enter valid 4-digit PIN values.');
    }

    final failures = <String>[];
    var pinMismatch = false;
    var invalidFormat = false;
    for (final repository in _backupRepositories) {
      Map<String, String>? payload;
      try {
        payload = await repository.restoreVmk(vaultId, interactive: true);
      } catch (error) {
        failures.add('${repository.runtimeType}: $error');
        continue;
      }
      if (payload == null) continue;

      try {
        await _restorePayload(
          vaultId: vaultId,
          payload: payload,
          originalPin: originalPin,
          newPin: newPin,
        );
        return;
      } on VaultBackupPinException {
        pinMismatch = true;
      } on VaultBackupFormatException {
        invalidFormat = true;
      }
    }

    if (failures.isNotEmpty) {
      final pinNote = pinMismatch
          ? ' One available copy could not be opened with that PIN.'
          : '';
      throw VaultBackupLookupException(
        'Could not restore this vault backup: ${failures.join('; ')}.$pinNote',
      );
    }
    if (pinMismatch) throw const VaultBackupPinException();
    if (invalidFormat) throw const VaultBackupFormatException();
    throw const VaultBackupNotFoundException();
  }

  Future<void> _restorePayload({
    required String vaultId,
    required Map<String, String> payload,
    required String originalPin,
    required String newPin,
  }) async {
    final wrappedVmk = _decode(payload['wrappedVmk']);
    final nonce = _decode(payload['nonce']);
    final mac = _decode(payload['mac']);
    final salt = _decode(payload['salt']);
    final version = int.tryParse(
      payload['encVersion'] ?? payload['encryptionVersion'] ?? '',
    );
    if (wrappedVmk == null ||
        nonce == null ||
        mac == null ||
        salt == null ||
        version == null ||
        wrappedVmk.isEmpty ||
        nonce.isEmpty ||
        mac.isEmpty ||
        salt.isEmpty ||
        version <= 0) {
      throw const VaultBackupFormatException();
    }

    List<int>? originalKek;
    List<int>? vmk;
    List<int>? newKek;
    try {
      try {
        originalKek = await _kdfService.deriveKey(originalPin, salt);
        vmk = await _cryptoService.unwrapKey(
          WrappedKey(
            keyId: vaultId,
            wrappedBytes: wrappedVmk,
            nonce: nonce,
            mac: mac,
            encryptionVersion: version,
          ),
          originalKek,
          aad: utf8.encode('$vaultId:vmk:v1'),
        );
        if (vmk.length != 32) throw const VaultBackupFormatException();
      } catch (_) {
        if (vmk != null && vmk.length != 32) {
          throw const VaultBackupFormatException();
        }
        throw const VaultBackupPinException();
      }

      final newSalt = _kdfService.generateSalt();
      newKek = await _kdfService.deriveKey(newPin, newSalt);
      final localEnvelope = await _cryptoService.wrapKey(
        vmk,
        newKek,
        keyId: vaultId,
        aad: utf8.encode('$vaultId:vmk:v1'),
      );

      final previousEnvelope = await _secureStorageRepository.loadWrappedVmk(
        vaultId,
      );
      final previousActiveVaultId = await _vaultRepository.getActiveVaultId();
      final newLocalVault = previousActiveVaultId == null;
      if (newLocalVault) {
        await _vaultRepository.markCreating(vaultId: vaultId);
      }

      try {
        await _secureStorageRepository.storeWrappedVmk(
          vaultId: vaultId,
          wrappedVmkBase64: base64Encode(localEnvelope.wrappedBytes),
          nonceBase64: base64Encode(localEnvelope.nonce),
          macBase64: base64Encode(localEnvelope.mac),
          saltBase64: base64Encode(newSalt),
          encVersion: localEnvelope.encryptionVersion,
        );
        await _vaultRepository.initializeVault(
          vaultId: vaultId,
          settings: VaultSettings.defaults(mode: UserMode.googleEnabled),
        );
        _vaultSession.unlock(vaultId: vaultId, vmkBytes: vmk, pin: newPin);
      } catch (_) {
        try {
          if (previousEnvelope == null) {
            await _secureStorageRepository.deleteVmkBlobs(vaultId);
          } else {
            await _secureStorageRepository.storeWrappedVmk(
              vaultId: vaultId,
              wrappedVmkBase64: previousEnvelope['wrappedVmk']!,
              nonceBase64: previousEnvelope['nonce']!,
              macBase64: previousEnvelope['mac']!,
              saltBase64: previousEnvelope['salt']!,
              encVersion: int.parse(previousEnvelope['encVersion']!),
            );
          }
        } finally {
          if (newLocalVault) {
            await _vaultRepository.deletePartialVault(vaultId: vaultId);
          }
        }
        rethrow;
      }
    } finally {
      _zero(originalKek);
      _zero(newKek);
      _zero(vmk);
    }
  }

  static List<int>? _decode(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      return base64Decode(value);
    } on FormatException {
      return null;
    }
  }

  static bool _isPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  static bool _isVaultId(String vaultId) =>
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(vaultId);

  static void _zero(List<int>? bytes) {
    try {
      bytes?.fillRange(0, bytes.length, 0);
    } catch (_) {}
  }
}
