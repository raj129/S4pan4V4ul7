import 'dart:convert';

import '../../crypto/services/crypto_service.dart';
import '../../domain/entities/user_mode.dart';
import '../../domain/entities/vault_settings.dart';
import '../../domain/repositories/secure_storage_repository.dart';
import '../../domain/repositories/vault_repository.dart';
import '../services/kdf_service.dart';
import '../services/vault_session.dart';
import 'package:uuid/uuid.dart';

/// Failure thrown when vault creation fails (partial state cleaned up).
class VaultCreationException implements Exception {
  const VaultCreationException(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() =>
      'VaultCreationException: $message${cause != null ? ' ($cause)' : ''}';
}

/// Orchestrates the complete vault creation pipeline:
///
/// 1. Generate vault ID
/// 2. Mark creation in-progress (for restart detection)
/// 3. Generate VMK
/// 4. Derive PIN-KEK via KDF
/// 5. Wrap VMK with PIN-KEK using AES-256-GCM
/// 6. Persist wrapped VMK in secure storage
/// 7. Write vault settings to local DB
/// 8. Zero VMK and KEK bytes (best-effort)
/// 9. Clean up on any failure
///
/// Security rules:
/// - VMK bytes are only created inside this use-case scope.
/// - VMK is NEVER returned to callers or placed in UI state.
/// - PIN is NEVER logged, stored, or returned.
class CreateVaultUseCase {
  const CreateVaultUseCase({
    required CryptoService cryptoService,
    required KdfService kdfService,
    required VaultRepository vaultRepository,
    required SecureStorageRepository secureStorageRepository,
    required VaultSession vaultSession,
  }) : _cryptoService = cryptoService,
       _kdfService = kdfService,
       _vaultRepository = vaultRepository,
       _secureStorageRepository = secureStorageRepository,
       _vaultSession = vaultSession;

  final CryptoService _cryptoService;
  final KdfService _kdfService;
  final VaultRepository _vaultRepository;
  final SecureStorageRepository _secureStorageRepository;
  final VaultSession _vaultSession;

  static const _uuid = Uuid();

  Future<String> execute({
    required String pin,
    required UserMode mode,
  }) async {
    final vaultId = _uuid.v4();
    List<int>? vmkBytes;
    List<int>? pinKek;

    try {
      // Step 1: mark creation in progress so a restart is detectable.
      await _vaultRepository.markCreating(vaultId: vaultId);

      // Step 2: generate VMK — 256-bit random key.
      vmkBytes = await _cryptoService.generateSymmetricKey();

      // Step 3: derive PIN-KEK from app PIN + fresh random salt.
      final salt = _kdfService.generateSalt();
      pinKek = await _kdfService.deriveKey(pin, salt);

      // Step 4: wrap (encrypt) VMK with PIN-KEK, binding to vaultId as AAD.
      final aad = utf8.encode('$vaultId:vmk:v1');
      final wrapped = await _cryptoService.wrapKey(
        vmkBytes,
        pinKek,
        keyId: vaultId,
        aad: aad,
      );

      // Step 5: persist wrapped VMK in secure storage (never plaintext VMK).
      await _secureStorageRepository.storeWrappedVmk(
        vaultId: vaultId,
        wrappedVmkBase64: base64Encode(wrapped.wrappedBytes),
        nonceBase64: base64Encode(wrapped.nonce),
        macBase64: base64Encode(wrapped.mac),
        saltBase64: base64Encode(salt),
        encVersion: _cryptoService.encryptionVersion,
      );

      // Step 6: write vault settings to local DB.
      final settings = VaultSettings.defaults(
        mode: mode,
      );
      await _vaultRepository.initializeVault(
        vaultId: vaultId,
        settings: settings,
      );
      _vaultSession.unlock(vaultId: vaultId, vmkBytes: vmkBytes);

      return vaultId;
    } catch (e) {
      // Clean up any partial state so the user can retry.
      await _cleanup(vaultId);
      throw VaultCreationException('Vault creation failed.', cause: e);
    } finally {
      // Best-effort zeroing: SensitiveBytes from the cryptography package is
      // unmodifiable, so we wrap in try-catch. Dart's GC handles cleanup when
      // zeroing is not possible.
      try {
        vmkBytes?.fillRange(0, vmkBytes.length, 0);
      } catch (_) {}
      try {
        pinKek?.fillRange(0, pinKek.length, 0);
      } catch (_) {}
    }
  }

  Future<void> _cleanup(String vaultId) async {
    try {
      await _vaultRepository.deletePartialVault(vaultId: vaultId);
    } catch (_) {}
    try {
      await _secureStorageRepository.deleteVmkBlobs(vaultId);
    } catch (_) {}
  }
}

extension _VaultSettingsCopyWith on VaultSettings {
  VaultSettings copyWith({bool? photoSyncEnabled}) {
    return VaultSettings(
      mode: mode,
      appLockOnOpen: appLockOnOpen,
      autoLockOnBackground: autoLockOnBackground,
      photoSyncEnabled: photoSyncEnabled ?? this.photoSyncEnabled,
      vmkBackupEnabled: vmkBackupEnabled,
    );
  }
}
