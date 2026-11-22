import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:photo_vault/features/vault/domain/repositories/secure_storage_repository.dart';

/// Derives and manages a domain-separated, one-way manifest backup key per vault.
///
/// Security model:
/// - Derived via `HKDF-SHA256(ikm: vmk, salt: vaultId, info: context)` while
///   the VMK is transiently unwrapped during vault create, unlock, or restore.
/// - Because HKDF is one-way, the stored backup key cannot recover the VMK or
///   decrypt individual photo blobs (whose DEKs remain wrapped under the VMK).
/// - Storing only this derived key in [SecureStorageRepository] enables
///   encrypted manifest backup/restore in both Local-only and Google modes,
///   including locked nightly WorkManager runs, without ever persisting raw VMK.
class VaultBackupKeyService {
  VaultBackupKeyService(this._secureStorage);

  final SecureStorageRepository _secureStorage;

  static const int _envelopeVersion = 4;
  static const int _nonceLength = 12;
  static const int _macLength = 16;
  static const String _hkdfInfo =
      'photo_vault/vault_photo_backup/manifest_key/v1';

  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final AesGcm _aesGcm = AesGcm.with256bits();
  static final Random _random = Random.secure();

  Future<bool> hasKey(String vaultId) async =>
      await _secureStorage.loadBackupKey(vaultId) != null;

  /// Derives and persists the manifest backup key for [vaultId] from [vmkBytes].
  Future<void> deriveAndStore({
    required String vaultId,
    required List<int> vmkBytes,
  }) async {
    List<int>? keyBytes;
    try {
      final derived = await _hkdf.deriveKey(
        secretKey: SecretKey(vmkBytes),
        nonce: utf8.encode(vaultId),
        info: utf8.encode(_hkdfInfo),
      );
      keyBytes = List<int>.from(await derived.extractBytes());
      await _secureStorage.storeBackupKey(
        vaultId: vaultId,
        backupKeyBase64: base64Encode(keyBytes),
      );
    } finally {
      if (keyBytes != null) {
        try {
          keyBytes.fillRange(0, keyBytes.length, 0);
        } catch (_) {}
      }
    }
  }

  /// Populates the backup key on unlock for vaults created before this key
  /// existed.
  Future<void> ensureStored({
    required String vaultId,
    required List<int> vmkBytes,
  }) async {
    if (await hasKey(vaultId)) return;
    await deriveAndStore(vaultId: vaultId, vmkBytes: vmkBytes);
  }

  /// Encrypts [plaintext] using the vault-bound key for [vaultId].
  ///
  /// Wire format: `[version(1)=4 || nonce(12) || ciphertext || mac(16)]`.
  Future<Uint8List> encryptManifest({
    required String vaultId,
    required List<int> plaintext,
  }) async {
    final keyB64 = await _secureStorage.loadBackupKey(vaultId);
    if (keyB64 == null) {
      throw StateError('Vault backup key is not initialised for $vaultId.');
    }
    final keyBytes = base64Decode(keyB64);
    try {
      final nonce = Uint8List.fromList(
        List<int>.generate(_nonceLength, (_) => _random.nextInt(256)),
      );
      final box = await _aesGcm.encrypt(
        plaintext,
        secretKey: SecretKey(keyBytes),
        nonce: nonce,
        aad: _aad(vaultId),
      );
      final out = BytesBuilder(copy: false)
        ..addByte(_envelopeVersion)
        ..add(nonce)
        ..add(box.cipherText)
        ..add(box.mac.bytes);
      return out.takeBytes();
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  /// Decrypts a `v4` vault-keyed manifest envelope for [vaultId].
  Future<Uint8List> decryptManifest({
    required String vaultId,
    required Uint8List encrypted,
  }) async {
    if (encrypted.length < 1 + _nonceLength + _macLength ||
        encrypted[0] != _envelopeVersion) {
      throw const FormatException('Not a v4 vault-keyed manifest.');
    }
    final keyB64 = await _secureStorage.loadBackupKey(vaultId);
    if (keyB64 == null) {
      throw StateError('Vault backup key is not initialised for $vaultId.');
    }
    final keyBytes = base64Decode(keyB64);
    try {
      final nonce = encrypted.sublist(1, 1 + _nonceLength);
      final macStart = encrypted.length - _macLength;
      final cipherText = encrypted.sublist(1 + _nonceLength, macStart);
      final mac = Mac(encrypted.sublist(macStart));
      final plain = await _aesGcm.decrypt(
        SecretBox(cipherText, nonce: nonce, mac: mac),
        secretKey: SecretKey(keyBytes),
        aad: _aad(vaultId),
      );
      return Uint8List.fromList(plain);
    } finally {
      keyBytes.fillRange(0, keyBytes.length, 0);
    }
  }

  static List<int> _aad(String vaultId) =>
      utf8.encode('photo_vault/vault_photo_backup/manifest/v4/$vaultId');
}
