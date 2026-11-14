import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/services/data_sms_protocol.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const thread = 'alice_bob';
  const id = '12345678-1234-4234-8234-123456789012';

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({
      'chat_key_account': 'alice',
      'chat_thread_key_$thread': base64Encode(List<int>.filled(32, 7)),
    });
  });

  Future<Uint8List> payload(String text) async {
    final crypto = ChatCryptoService();
    return DataSmsProtocol.pack(
      thread,
      await crypto.encryptMessage(
        threadId: thread,
        plaintext: DataSmsProtocol.body(
          id: id,
          threadId: thread,
          senderId: 'alice',
          recipientId: 'bob',
          sentAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          text: text,
        ),
      ),
    );
  }

  DataSmsEstimate estimate(String text) => DataSmsProtocol.estimate(
    text: text,
    threadId: thread,
    senderId: 'alice',
    recipientId: 'bob',
  );

  test(
    'counter equals actual binary encrypted payload for Unicode and escapes',
    () async {
      for (final text in [
        'hello',
        '  hello  ',
        'नमस्ते',
        '👨‍👩‍👧‍👦',
        '"\\\n\t',
      ]) {
        final bytes = await payload(text);
        expect(
          estimate(text).segments,
          DataSmsProtocol.segmentCount(bytes.length),
        );
        final wire = DataSmsProtocol.unpack(bytes);
        expect(wire.threadId, thread);
        final plain = await ChatCryptoService().decryptMessage(
          threadId: thread,
          encryptedB64: wire.ciphertext,
        );
        final envelope = jsonDecode(plain) as Map;
        expect(envelope['text'], text.trim());
        expect(envelope['id'], id);
        expect(envelope['r'], 'bob');
        expect(envelope['t'], thread);
      }
      expect(estimate('👨‍👩‍👧‍👦').characters, 1);
      expect(estimate('   ').characters, 0);
      expect(estimate('   ').segments, 0);
    },
  );

  test('AES-GCM overhead is included without Base64 wire expansion', () async {
    final bytes = await payload('hello');
    final decoded = DataSmsProtocol.unpack(bytes);
    final encryptedBytes = base64Decode(decoded.ciphertext);
    final plain = await ChatCryptoService().decryptMessage(
      threadId: thread,
      encryptedB64: decoded.ciphertext,
    );
    expect(encryptedBytes.length, utf8.encode(plain).length + 28);
    expect(
      bytes.length,
      2 + utf8.encode(thread).length + encryptedBytes.length,
    );
  });

  test(
    'physical segment boundaries and hard cap match actual serialization',
    () async {
      expect(DataSmsProtocol.segmentCount(99), 1);
      expect(DataSmsProtocol.segmentCount(100), 2);
      expect(DataSmsProtocol.segmentCount(990), 10);
      expect(DataSmsProtocol.segmentCount(991), 11);
      var maxText = '';
      while (estimate('${maxText}x').segments <= 10) {
        maxText += 'x';
      }
      expect(estimate(maxText).segments, 10);
      expect((await payload(maxText)).length, 990);
      expect(estimate('${maxText}x').segments, 11);
      await expectLater(payload('${maxText}x'), throwsFormatException);
    },
  );

  test('malformed binary routing and oversized payloads are rejected', () {
    for (final bytes in [
      Uint8List(0),
      Uint8List(31),
      Uint8List(991),
      Uint8List.fromList([255, 255, ...List.filled(29, 0)]),
    ]) {
      expect(() => DataSmsProtocol.unpack(bytes), throwsFormatException);
    }
  });

  test('mixed transport cache and backup codec retain SMS state', () {
    final internet = ChatMessage(
      messageId: 'old',
      threadId: thread,
      senderId: 'alice',
      encryptedText: 'encrypted',
      sentAt: DateTime.utc(2026),
      deletedFor: const [],
    );
    expect(
      CachedMessageCodec.decode(CachedMessageCodec.encode(internet))!.transport,
      MessageTransport.internet,
    );
    final sms = ChatMessage(
      messageId: id,
      threadId: thread,
      senderId: 'alice',
      encryptedText: 'encrypted',
      sentAt: DateTime.utc(2026),
      deletedFor: const [],
      transport: MessageTransport.dataSms,
      smsSegments: 3,
      smsDeliveryState: 'unconfirmed',
      smsError: 'Report unavailable',
    );
    final restored = CachedMessageCodec.decode(CachedMessageCodec.encode(sms))!;
    expect(restored, sms);
    expect(restored.copyWith(localDecryptedText: 'hello').smsSegments, 3);
    expect(restored.copyWith(localDecryptedText: 'hello').isDataSms, isTrue);
  });
}
