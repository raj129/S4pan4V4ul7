import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_decryption.dart';

void main() {
  test(
    'worker authenticates existing format without modifying caller buffers',
        () async {
      final keyBytes = Uint8List.fromList(List.generate(32, (i) => i));
      final key = SecretKey(keyBytes);
      final plain = Uint8List.fromList(
        List.generate(1024 * 1024, (i) => i % 251),
      );
      final box = await AesGcm.with256bits().encrypt(
        plain,
        secretKey: key,
        nonce: List<int>.filled(12, 7),
      );
      final encrypted = Uint8List.fromList([
        ...box.nonce,
        ...box.cipherText,
        ...box.mac.bytes,
      ]);
      final before = Uint8List.fromList(encrypted);
      final result = await decryptChatMediaInWorker(encrypted, key);
      expect(result, plain);
      expect(encrypted, before);
      expect(keyBytes, List.generate(32, (i) => i));
    },
  );

  test('worker rejects unauthenticated and truncated media', () async {
    final key = SecretKey(List<int>.filled(32, 1));
    await expectLater(
      decryptChatMediaInWorker(Uint8List(20), key),
      throwsFormatException,
    );
    await expectLater(
      decryptChatMediaInWorker(Uint8List(100), key),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });
}
