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
    final sentAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    return DataSmsProtocol.packV2(
      sentAtMs: sentAtMs,
      encryptedBytes: await crypto.encryptDataSms(
        threadId: thread,
        sentAtMs: sentAtMs,
        plaintext: text.trim(),
      ),
    );
  }

  DataSmsEstimate estimate(String text) => DataSmsProtocol.estimate(
    text: text,
    threadId: thread,
    senderId: 'alice',
    recipientId: 'bob',
  );

  test('V2 counter matches actual encrypted wire bytes', () async {
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
      final packet = DataSmsProtocol.unpack(bytes);
      expect(packet.version, 2);
      expect(packet.threadId, isNull);
      expect(
        await ChatCryptoService().decryptDataSms(
          threadId: thread,
          sentAtMs: packet.sentAtMs!,
          encryptedBytes: packet.encryptedBytes!,
        ),
        text.trim(),
      );
    }
    expect(estimate('👨‍👩‍👧‍👦').characters, 1);
    expect(estimate('   ').characters, 0);
    expect(estimate('   ').segments, 0);
  });

  test('V2 envelope adds exactly 35 bytes without Base64 expansion', () async {
    final bytes = await payload('hello');
    final packet = DataSmsProtocol.unpack(bytes);
    expect(packet.encryptedBytes!.length, utf8.encode('hello').length + 28);
    expect(bytes.length, utf8.encode('hello').length + 35);
  });

  test('malformed compact timestamps and short ciphertext are rejected', () {
    expect(
      () => DataSmsProtocol.packV2(
        sentAtMs: 1 << 48,
        encryptedBytes: Uint8List(28),
      ),
      throwsFormatException,
    );
    expect(
      () => DataSmsProtocol.packV2(sentAtMs: 1, encryptedBytes: Uint8List(27)),
      throwsFormatException,
    );
    expect(
      () => DataSmsProtocol.unpack(
        Uint8List.fromList([2, ...List.filled(33, 0)]),
      ),
      throwsFormatException,
    );
  });

  test('timestamp is authenticated and cannot be changed in transit', () async {
    final bytes = await payload('authenticated');
    final packet = DataSmsProtocol.unpack(bytes);
    expect(
      () => ChatCryptoService().decryptDataSms(
        threadId: thread,
        sentAtMs: packet.sentAtMs! + 1,
        encryptedBytes: packet.encryptedBytes!,
      ),
      throwsA(isA<Exception>()),
    );
  });

  test('one SMS carries up to 77 ASCII characters at 112 app bytes', () async {
    expect(DataSmsProtocol.segmentCount(112), 1);
    expect(DataSmsProtocol.segmentCount(113), 2);
    expect(estimate('x' * 77).segments, 1);
    expect(estimate('x' * 78).segments, 2);
    expect((await payload('x' * 77)).length, 112);
    expect(DataSmsProtocol.segmentCount(1120), 10);
    expect(DataSmsProtocol.segmentCount(1121), 11);
    expect(estimate('x' * 1085).segments, 10);
    expect(estimate('x' * 1086).segments, 11);
    await expectLater(payload('x' * 1086), throwsFormatException);
  });

  test(
    'legacy V1 packet round-trips and malformed packets are rejected',
    () async {
      final crypto = ChatCryptoService();
      final legacyCiphertext = await crypto.encryptMessage(
        threadId: thread,
        plaintext: DataSmsProtocol.body(
          id: id,
          threadId: thread,
          senderId: 'alice',
          recipientId: 'bob',
          sentAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          text: 'old message',
        ),
      );
      final legacy = DataSmsProtocol.pack(thread, legacyCiphertext);
      final decoded = DataSmsProtocol.unpack(legacy);
      expect(decoded.version, 1);
      expect(decoded.threadId, thread);
      expect(decoded.ciphertext, legacyCiphertext);

      for (final bytes in [
        Uint8List(0),
        Uint8List(31),
        Uint8List(1121),
        Uint8List.fromList([255, 255, ...List.filled(29, 0)]),
        Uint8List.fromList([2, 0]),
      ]) {
        expect(() => DataSmsProtocol.unpack(bytes), throwsFormatException);
      }
    },
  );

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
      smsSegments: 1,
      smsDeliveryState: 'unconfirmed',
      smsError: 'Report unavailable',
    );
    final restored = CachedMessageCodec.decode(CachedMessageCodec.encode(sms))!;
    expect(restored, sms);
    expect(restored.copyWith(localDecryptedText: 'hello').smsSegments, 1);
    expect(restored.copyWith(localDecryptedText: 'hello').isDataSms, isTrue);
  });
}
