import 'dart:convert';

import '../../application/services/kdf_service.dart';
import '../../crypto/models/wrapped_key.dart';
import '../../crypto/services/crypto_service.dart';
import '../../domain/repositories/secure_storage_repository.dart';
import '../../domain/repositories/vault_repository.dart';

/// Verifies app PIN by attempting to unwrap the stored VMK envelope.
///
/// Returns true when PIN is correct; false otherwise.
/// Raw key material is kept only within this use case and zeroed best-effort.
class UnlockVaultUseCase {
  const UnlockVaultUseCase({
    required VaultRepository vaultRepository,
    required SecureStorageRepository secureStorageRepository,
    required KdfService kdfService,
    required CryptoService cryptoService,
  }) : _vaultRepository = vaultRepository,
       _secureStorageRepository = secureStorageRepository,
       _kdfService = kdfService,
       _cryptoService = cryptoService;

  final VaultRepository _vaultRepository;
  final SecureStorageRepository _secureStorageRepository;
  final KdfService _kdfService;
  final CryptoService _cryptoService;

  Future<bool> execute(String pin) async {
    List<int>? derivedKey;
    List<int>? vmk;
    try {
      final vaultId = await _vaultRepository.getActiveVaultId();
      if (vaultId == null || vaultId.isEmpty) return false;

      final wrappedRecord = await _secureStorageRepository.loadWrappedVmk(vaultId);
      if (wrappedRecord == null) return false;

      final wrappedVmkB64 = wrappedRecord['wrappedVmk'];
      final nonceB64 = wrappedRecord['nonce'];
      final macB64 = wrappedRecord['mac'];
      final saltB64 = wrappedRecord['salt'];
      final encVersionRaw = wrappedRecord['encVersion'];
      if (wrappedVmkB64 == null ||
          nonceB64 == null ||
          macB64 == null ||
          saltB64 == null ||
          encVersionRaw == null) {
        return false;
      }

      final salt = base64Decode(saltB64);
      derivedKey = await _kdfService.deriveKey(pin, salt);

      final wrapped = WrappedKey(
        keyId: vaultId,
        wrappedBytes: base64Decode(wrappedVmkB64),
        nonce: base64Decode(nonceB64),
        mac: base64Decode(macB64),
        encryptionVersion: int.tryParse(encVersionRaw) ?? 1,
      );

      final aad = utf8.encode('$vaultId:vmk:v1');
      vmk = await _cryptoService.unwrapKey(wrapped, derivedKey, aad: aad);
      return vmk.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      try {
        derivedKey?.fillRange(0, derivedKey.length, 0);
      } catch (_) {}
      try {
        vmk?.fillRange(0, vmk.length, 0);
      } catch (_) {}
    }
  }
}
