import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../models/encrypted_payload.dart';
import '../models/wrapped_key.dart';
import 'crypto_service.dart';

class AesGcmCryptoService implements CryptoService {
  AesGcmCryptoService({AesGcm? algorithm, this.version = 1})
    : _algorithm = algorithm ?? AesGcm.with256bits();

  final AesGcm _algorithm;
  final int version;
  final Random _random = Random.secure();

  @override
  int get encryptionVersion => version;

  @override
  Future<List<int>> generateSymmetricKey() async {
    final secretKey = await _algorithm.newSecretKey();
    return secretKey.extractBytes();
  }

  @override
  Future<EncryptedPayload> encrypt(
    List<int> plainText,
    List<int> keyBytes, {
    List<int>? aad,
  }) async {
    final nonce = List<int>.generate(12, (_) => _random.nextInt(256));
    final box = await _algorithm.encrypt(
      plainText,
      secretKey: SecretKey(keyBytes),
      nonce: nonce,
      aad: aad ?? const <int>[],
    );

    return EncryptedPayload(
      nonce: box.nonce,
      cipherText: box.cipherText,
      mac: box.mac.bytes,
      encryptionVersion: encryptionVersion,
    );
  }

  @override
  Future<List<int>> decrypt(
    EncryptedPayload payload,
    List<int> keyBytes, {
    List<int>? aad,
  }) {
    final box = SecretBox(
      payload.cipherText,
      nonce: payload.nonce,
      mac: Mac(payload.mac),
    );

    return _algorithm.decrypt(
      box,
      secretKey: SecretKey(keyBytes),
      aad: aad ?? const <int>[],
    );
  }

  @override
  Future<WrappedKey> wrapKey(
    List<int> keyToWrap,
    List<int> wrappingKey, {
    required String keyId,
    List<int>? aad,
  }) async {
    final payload = await encrypt(
      keyToWrap,
      wrappingKey,
      aad: aad ?? const <int>[],
    );
    return WrappedKey(
      keyId: keyId,
      wrappedBytes: payload.cipherText,
      nonce: payload.nonce,
      mac: payload.mac,
      encryptionVersion: payload.encryptionVersion,
    );
  }

  @override
  Future<List<int>> unwrapKey(
    WrappedKey wrappedKey,
    List<int> wrappingKey, {
    List<int>? aad,
  }) {
    return decrypt(
      EncryptedPayload(
        nonce: wrappedKey.nonce,
        cipherText: wrappedKey.wrappedBytes,
        mac: wrappedKey.mac,
        encryptionVersion: wrappedKey.encryptionVersion,
      ),
      wrappingKey,
      aad: aad ?? const <int>[],
    );
  }
}
