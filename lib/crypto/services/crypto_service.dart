import '../models/encrypted_payload.dart';
import '../models/wrapped_key.dart';

abstract class CryptoService {
  int get encryptionVersion;

  Future<List<int>> generateSymmetricKey();

  Future<EncryptedPayload> encrypt(
    List<int> plainText,
    List<int> keyBytes, {
    List<int>? aad,
  });

  Future<List<int>> decrypt(
    EncryptedPayload payload,
    List<int> keyBytes, {
    List<int>? aad,
  });

  Future<WrappedKey> wrapKey(
    List<int> keyToWrap,
    List<int> wrappingKey, {
    required String keyId,
    List<int>? aad,
  });

  Future<List<int>> unwrapKey(
    WrappedKey wrappedKey,
    List<int> wrappingKey, {
    List<int>? aad,
  });
}
