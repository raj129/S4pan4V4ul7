import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/chat_media_cache.dart';
import 'package:photo_vault/application/services/chat_receive_service.dart';
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/repositories/message_repository.dart';
import '../helpers/memory_message_cache.dart';

class _Messages implements MessageRepository {
  int delivered = 0;
  ChatMessage message = ChatMessage(
    messageId: 'm',
    threadId: 'alice_bob',
    senderId: 'bob',
    encryptedText: 'ciphertext',
    sentAt: DateTime.utc(2026),
    deletedFor: const [],
    mediaType: MessageType.image,
    mediaRef: 'chat_media/alice_bob/m/media.enc',
  );
  @override
  Future<ChatMessage?> getMessage({
    required String threadId,
    required String messageId,
  }) async => message;
  @override
  Future<void> markDelivered({
    required String threadId,
    required List<String> messageIds,
    required String uid,
  }) async {
    delivered++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Media implements MediaRepository {
  int downloads = 0;
  @override
  Future<Uint8List> downloadEncryptedMedia(String storagePath) async {
    downloads++;
    return Uint8List.fromList([42, 99]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Crypto implements ChatCryptoService {
  bool keyAvailable = true;
  @override
  Future<String> decryptMessage({
    required String threadId,
    required String encryptedB64,
  }) async {
    if (!keyAvailable) throw StateError('Missing key');
    return 'never persisted';
  }

  @override
  Future<Uint8List> decryptMedia({
    required String threadId,
    required Uint8List encryptedBytes,
  }) async => Uint8List.fromList([7, 8]);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late ChatMediaCache disk;
  late _Messages messages;
  late _Media media;
  late _Crypto crypto;
  late MemoryMessageCache messageCache;
  late ChatReceiveService receiver;
  String? uid;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat_receive');
    disk = ChatMediaCache(directory: directory);
    messages = _Messages();
    media = _Media();
    crypto = _Crypto();
    messageCache = MemoryMessageCache();
    uid = 'alice';
    receiver = ChatReceiveService(
      messages: messages,
      messageCache: messageCache,
      media: media,
      crypto: crypto,
      cache: disk,
      currentUid: () => uid,
    );
  });
  tearDown(() => directory.delete(recursive: true));
  Future<void> receive() =>
      receiver.process(uid: 'alice', threadId: 'alice_bob', messageId: 'm');

  test(
    'received media is stored encrypted without any vault dependency',
    () async {
      await receive();
      expect(await disk.read('alice:${messages.message.mediaRef}'), [42, 99]);
      expect(messageCache.rows['m']!.encryptedText, 'ciphertext');
      expect(
        messageCache.rows['m']!.payloadJson,
        isNot(contains('never persisted')),
      );
      expect(messages.delivered, 1);
    },
  );

  test('duplicate receive events reuse authenticated ciphertext', () async {
    await receive();
    await receive();
    expect(media.downloads, 1);
  });

  test('moved full media is not automatically downloaded again', () async {
    await disk.markMoved('alice:${messages.message.mediaRef}');
    await receive();
    expect(media.downloads, 0);
  });

  test(
    'missing keys neither cache messages nor acknowledge delivery',
    () async {
      crypto.keyAvailable = false;
      await expectLater(receive(), throwsStateError);
      expect(messageCache.rows, isEmpty);
      expect(messages.delivered, 0);
    },
  );

  test('cleared history is not silently restored by a receive job', () async {
    messageCache.cleared['alice_bob'] = DateTime.utc(2026, 1, 2);
    await receive();
    expect(messageCache.rows, isEmpty);
    expect(media.downloads, 0);
    expect(messages.delivered, 0);
  });

  test(
    'untrusted attachment path never downloads outside the message',
    () async {
      messages.message = messages.message.copyWith(
        mediaRef: 'chat_media/another_thread/m/media.enc',
      );
      await expectLater(receive(), throwsFormatException);
      expect(media.downloads, 0);
    },
  );

  test('account mismatch stops processing before fetching', () async {
    uid = 'bob';
    await expectLater(receive(), throwsA(isA<ChatReceiveAccountChanged>()));
    expect(media.downloads, 0);
    expect(messages.delivered, 0);
  });
}
