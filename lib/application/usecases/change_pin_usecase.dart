import 'dart:convert';

import '../../crypto/models/wrapped_key.dart';
import '../../crypto/services/crypto_service.dart';
import '../../domain/repositories/secure_storage_repository.dart';
import '../../domain/repositories/vault_repository.dart';
import '../services/kdf_service.dart';
import '../services/vault_session.dart';

class ChangePinException implements Exception {
  final String message;
  ChangePinException(this.message);
  @override
  String toString() => 'ChangePinException: $message';
}

class ChangePinUseCase {
  const ChangePinUseCase({
    required VaultRepository vaultRepository,
    required SecureStorageRepository secureStorageRepository,
    required KdfService kdfService,
    required CryptoService cryptoService,
    required VaultSession vaultSession,
  }) : _vaultRepository = vaultRepository,
       _secureStorageRepository = secureStorageRepository,
       _kdfService = kdfService,
       _cryptoService = cryptoService,
       _vaultSession = vaultSession;

  final VaultRepository _vaultRepository;
  final SecureStorageRepository _secureStorageRepository;
  final KdfService _kdfService;
  final CryptoService _cryptoService;
  final VaultSession _vaultSession;

  Future<void> execute({
    required String oldPin,
    required String newPin,
  }) async {
    List<int>? oldDerivedKey;
    List<int>? vmk;
    List<int>? newDerivedKey;
    
    try {
      final vaultId = await _vaultRepository.getActiveVaultId();
      if (vaultId == null) throw ChangePinException('No active vault found.');

      // 1. Verify old PIN and get VMK
      final wrappedRecord = await _secureStorageRepository.loadWrappedVmk(vaultId);
      if (wrappedRecord == null) throw ChangePinException('Vault key material missing.');

      final salt = base64Decode(wrappedRecord['salt']!);
      oldDerivedKey = await _kdfService.deriveKey(oldPin, salt);

      final wrapped = WrappedKey(
        keyId: vaultId,
        wrappedBytes: base64Decode(wrappedRecord['wrappedVmk']!),
        nonce: base64Decode(wrappedRecord['nonce']!),
        mac: base64Decode(wrappedRecord['mac']!),
        encryptionVersion: int.parse(wrappedRecord['encVersion']!),
      );

      final aad = utf8.encode('$vaultId:vmk:v1');
      vmk = await _cryptoService.unwrapKey(wrapped, oldDerivedKey, aad: aad);
      
      if (vmk.isEmpty) {
        throw ChangePinException('Incorrect old PIN.');
      }

      // 2. Wrap VMK with new PIN
      final newSalt = _kdfService.generateSalt();
      newDerivedKey = await _kdfService.deriveKey(newPin, newSalt);

      final newWrapped = await _cryptoService.wrapKey(
        vmk,
        newDerivedKey,
        keyId: vaultId,
        aad: aad,
      );

      // 3. Persist new wrapped VMK
      await _secureStorageRepository.storeWrappedVmk(
        vaultId: vaultId,
        wrappedVmkBase64: base64Encode(newWrapped.wrappedBytes),
        nonceBase64: base64Encode(newWrapped.nonce),
        macBase64: base64Encode(newWrapped.mac),
        saltBase64: base64Encode(newSalt),
        encVersion: _cryptoService.encryptionVersion,
      );

      // 4. Update session just in case
      _vaultSession.unlock(vaultId: vaultId, vmkBytes: vmk);

    } catch (e) {
      if (e is ChangePinException) rethrow;
      throw ChangePinException('Failed to change PIN: $e');
    } finally {
      // Best-effort zeroing
      try {
        oldDerivedKey?.fillRange(0, oldDerivedKey.length, 0);
      } catch (_) {}
      try {
        vmk?.fillRange(0, vmk.length, 0);
      } catch (_) {}
      try {
        newDerivedKey?.fillRange(0, newDerivedKey.length, 0);
      } catch (_) {}
    }
  }
}
