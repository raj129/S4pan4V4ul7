import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/crypto/services/aes_gcm_crypto_service.dart';

void main() {
  group('AesGcmCryptoService', () {
    test('encrypt/decrypt roundtrip', () async {
      final service = AesGcmCryptoService();
      final key = await service.generateSymmetricKey();
      final plainText = 'vault-photo-bytes'.codeUnits;
      final aad = 'photo:test-id:v1'.codeUnits;

      final encrypted = await service.encrypt(plainText, key, aad: aad);
      final decrypted = await service.decrypt(encrypted, key, aad: aad);

      expect(decrypted, plainText);
      expect(encrypted.encryptionVersion, service.encryptionVersion);
    });

    test('wrap/unwrap key roundtrip', () async {
      final service = AesGcmCryptoService();
      final vmk = await service.generateSymmetricKey();
      final dek = await service.generateSymmetricKey();

      final wrapped = await service.wrapKey(
        dek,
        vmk,
        keyId: 'photo-1',
        aad: 'wrap:photo-1'.codeUnits,
      );

      final unwrapped = await service.unwrapKey(
        wrapped,
        vmk,
        aad: 'wrap:photo-1'.codeUnits,
      );

      expect(unwrapped, dek);
    });
  });
}
