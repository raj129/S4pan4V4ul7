import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_local_media.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_downloads.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_cache.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_loader.dart';
import 'package:photo_vault/features/chat/application/services/chat_receive_service.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import '../helpers/memory_message_cache.dart';

class _ReceiptMessages implements MessageRepository {
  _ReceiptMessages(this.message);

  final ChatMessage message;

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
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoBackgroundMediaDecryption extends ChatCryptoService {
  @override
  Future<Uint8List> decryptMedia({
    required String threadId,
    required Uint8List encryptedBytes,
  }) => throw StateError('Background receipt must not materialize plaintext.');
}

class _Remote implements MediaRepository {
  int reads = 0;
  late Uint8List ciphertext;

  @override
  Future<Uint8List> downloadEncryptedMedia(String path) async {
    reads++;
    return ciphertext.asUnmodifiableView();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ReadOnlyCodec extends StandardMethodCodec {
  const _ReadOnlyCodec();

  @override
  dynamic decodeEnvelope(ByteData envelope) {
    final value = super.decodeEnvelope(envelope);
    return value is Uint8List ? value.asUnmodifiableView() : value;
  }
}

/// Protocol fixture with real encrypted files; production storage is untouched.
class _LocalBackend {
  _LocalBackend(this.root);

  final Directory root;
  final records = <String, Map<String, Object?>>{};
  bool full = false;
  bool denied = false;
  int writes = 0;
  int sourceReads = 0;
  Uint8List original = Uint8List.fromList([4, 5, 6]);

  File file(String path) =>
      File(
        '${root.path}${Platform.pathSeparator}${sha256.convert(
            utf8.encode(path))}.enc',
      );

  Future<Object?> call(MethodCall call) async {
    final args = Map<String, Object?>.from(call.arguments as Map);
    expect(args['uid'], 'alice');
    final path = args['path'] as String?;
    switch (call.method) {
      case 'metadata':
        return records[path];
      case 'read':
        final record = records[path];
        if (record == null || record['moved'] == true) return null;
        final bytes = await file(path!).readAsBytes();
        if (sha256.convert(bytes).toString() != record['digest']) {
          throw PlatformException(
            code: 'local_media_corrupt',
            message: 'Encrypted local file is damaged. Retry to repair it.',
          );
        }
        return bytes;
      case 'put':
        if (full) {
          throw PlatformException(
            code: 'local_media_storage_full',
            message:
            'Chat media storage is full. Remove attachments and retry.',
          );
        }
        final bytes = args['bytes'] as Uint8List;
        await file(path!).writeAsBytes(bytes, flush: true);
        records[path] = {
          'direction': args['direction'],
          'moved': false,
          'digest': sha256.convert(bytes).toString(),
          if (args['sourceUri'] != null) 'sourceUri': args['sourceUri'],
          if (args['sourceDigest'] != null)
            'sourceDigest': args['sourceDigest'],
          'sourceFlags': args['sourceFlags'] ?? 0,
        };
        writes++;
        return null;
      case 'remove':
      case 'markMoved':
        final target = file(path!);
        if (await target.exists()) await target.delete();
        if (call.method == 'markMoved') {
          records[path] = {'direction': 'received', 'moved': true};
        } else {
          records.remove(path);
        }
        return null;
      default:
        throw StateError('Unexpected local media command');
    }
  }

  Future<Object?> source(MethodCall call) async {
    expect(call.method, 'readSource');
    sourceReads++;
    if (denied) {
      throw PlatformException(
        code: 'source_permission_denied',
        message: 'The original URI grant is unavailable.',
      );
    }
    return {'bytes': original.asUnmodifiableView()};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const localChannel = MethodChannel('test/local_media', _ReadOnlyCodec());
  const sourceChannel = MethodChannel('test/local_source');
  const path = 'chat_media/alice_bob/example/media.enc';
  late Directory directory;
  late _LocalBackend backend;
  late AndroidChatLocalMedia local;
  late ChatMediaCache legacy;
  late AndroidChatMediaCache cache;
  late ChatCryptoService crypto;
  late _Remote remote;
  late ChatMediaLoader loader;
  final plain = Uint8List.fromList([1, 2, 3]);
  ChatMediaLoader freshLoader() =>
      ChatMediaLoader(
        mediaRepository: remote,
        cryptoService: crypto,
        diskCache: cache,
        localMedia: local,
        accountId: 'alice',
        loadTimeout: const Duration(seconds: 5),
      );
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({
      'chat_thread_key_alice_bob': base64.encode(List<int>.filled(32, 7)),
    });
    directory = await Directory.systemTemp.createTemp('chat_local_integration');
    backend = _LocalBackend(
      await Directory(
        '${directory.path}${Platform.pathSeparator}completed',
      ).create(),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(localChannel, backend.call);
    messenger.setMockMethodCallHandler(sourceChannel, backend.source);
    local = const AndroidChatLocalMedia(
      channel: localChannel,
      sourceChannel: sourceChannel,
    );
    legacy = ChatMediaCache(
      directory: Directory('${directory.path}${Platform.pathSeparator}legacy'),
    );
    cache = AndroidChatMediaCache(
      localMedia: local,
      currentUid: () => 'alice',
      legacy: legacy,
    );
    crypto = ChatCryptoService();
    remote = _Remote()
      ..ciphertext = await crypto.encryptMedia(
        threadId: 'alice_bob',
        bytes: plain,
      );
    loader = freshLoader();
  });
  tearDown(() async {
    loader.dispose();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(localChannel, null);
    messenger.setMockMethodCallHandler(sourceChannel, null);
    await directory.delete(recursive: true);
  });

  test(
    'receive commit then reopen through a new loader without downloading',
        () async {
      final first = await loader.fetchUncached(
        threadId: 'alice_bob',
        storagePath: path,
        senderId: 'bob',
      );
      expect(first, plain);
      expect(remote.reads, 1);
      expect(await backend.file(path).readAsBytes(), remote.ciphertext);
      expect(await backend.file(path).readAsBytes(), isNot(plain));
      first.fillRange(0, first.length, 0);
      loader.dispose();
      loader = freshLoader();
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'bob',
        ),
        plain,
      );
      expect(remote.reads, 1);
      expect(backend.writes, 1);
    },
  );

  test(
    'legacy authenticated received copy migrates without network access',
        () async {
      await legacy.write('alice:$path', remote.ciphertext);
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'bob',
        ),
        plain,
      );
      expect(remote.reads, 0);
      expect(await legacy.read('alice:$path'), isNull);
      expect(await backend.file(path).exists(), isTrue);
    },
  );

  test(
    'background receipt stores ciphertext and defers media decryption until preview',
        () async {
      final message = ChatMessage(
        messageId: 'example',
        threadId: 'alice_bob',
        senderId: 'bob',
        encryptedText: await crypto.encryptMessage(
          threadId: 'alice_bob',
          plaintext: 'received caption',
        ),
        sentAt: DateTime.utc(2026),
        deletedFor: const [],
        mediaType: MessageType.image,
        mediaRef: path,
      );
      final receive = ChatReceiveService(
        messages: _ReceiptMessages(message),
        messageCache: MemoryMessageCache(),
        media: remote,
        crypto: _NoBackgroundMediaDecryption(),
        cache: cache,
        currentUid: () => 'alice',
      );
      await receive.process(
        uid: 'alice',
        threadId: 'alice_bob',
        messageId: 'example',
      );
      expect(await backend.file(path).readAsBytes(), remote.ciphertext);
      expect(remote.reads, 1);
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'bob',
        ),
        plain,
      );
      expect(remote.reads, 1);
    },
  );

  Future<void> sent({bool original = true}) =>
      local.put(
        uid: 'alice',
        path: path,
        direction: ChatMediaDirection.sent,
        ciphertext: remote.ciphertext,
        sourceUri: original ? 'content://fixture/document/1' : null,
        sourceDigest: original
            ? sha256.convert(backend.original).toString()
            : null,
        sourceFlags: original ? 1 : 0,
      );

  test(
    'unresponsive original provider falls back without a remote download',
        () async {
      await sent();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        sourceChannel,
            (_) => Completer<Object?>().future,
      );
      local = const AndroidChatLocalMedia(
        channel: localChannel,
        sourceChannel: sourceChannel,
        sourceReadTimeout: Duration(milliseconds: 20),
      );
      loader.dispose();
      loader = freshLoader();
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'alice',
        ),
        plain,
      );
      expect(remote.reads, 0);
    },
  );

  test(
    'sent original source is preferred over the encrypted sent variant',
        () async {
      await sent();
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'alice',
        ),
        backend.original,
      );
      expect(backend.sourceReads, 1);
      expect(remote.reads, 0);
    },
  );

  test(
    'revoked original permission falls back to local sent ciphertext only',
        () async {
      await sent();
      backend.denied = true;
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'alice',
        ),
        plain,
      );
      expect(remote.reads, 0);
    },
  );

  test(
    'changed original file cannot masquerade as the sent attachment',
        () async {
      await sent();
      backend.original = Uint8List.fromList([9, 9, 9]);
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'alice',
        ),
        plain,
      );
      expect(backend.original, [9, 9, 9]);
      expect(remote.reads, 0);
    },
  );

  test('missing sent source and copy fails without a server request', () async {
    await expectLater(
      loader.fetchUncached(
        threadId: 'alice_bob',
        storagePath: path,
        senderId: 'alice',
      ),
      throwsA(
        isA<ChatLocalMediaException>().having(
              (error) => error.code,
          'code',
          'source_unavailable',
        ),
      ),
    );
    expect(remote.reads, 0);
  });

  test(
    'legacy completed sent staging is adopted without enqueue or network',
        () async {
      const stage = MethodChannel('test/legacy_sent_stage', _ReadOnlyCodec());
      final calls = <String>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(stage, (call) async {
        calls.add(call.method);
        if (call.method == 'list') {
          return [
            {
              'uid': 'alice',
              'threadId': 'alice_bob',
              'storagePath': path,
              'state': 'completed',
              'processedBytes': remote.ciphertext.length,
              'totalBytes': remote.ciphertext.length,
            },
          ];
        }
        if (call.method == 'read') return remote.ciphertext;
        throw StateError('A sent attachment must not start a download.');
      });
      final downloads = AndroidChatDownloads(
        currentUid: () => 'alice',
        channel: stage,
      );
      addTearDown(() {
        downloads.dispose();
        messenger.setMockMethodCallHandler(stage, null);
      });
      loader.dispose();
      loader = ChatMediaLoader(
        mediaRepository: remote,
        cryptoService: crypto,
        diskCache: cache,
        localMedia: local,
        downloads: downloads,
        accountId: 'alice',
      );
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'alice',
        ),
        plain,
      );
      expect(remote.reads, 0);
      expect(calls, ['list', 'read']);
      expect(backend.records[path]?['direction'], 'sent');
    },
  );

  test(
    'local corruption is explicit and repair requires received retry',
        () async {
      await local.put(
        uid: 'alice',
        path: path,
        direction: ChatMediaDirection.received,
        ciphertext: remote.ciphertext,
      );
      await backend.file(path).writeAsBytes(Uint8List(29), flush: true);
      await expectLater(
        loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'bob',
        ),
        throwsA(isA<ChatLocalMediaException>()),
      );
      expect(remote.reads, 0);
      await loader.retryFailedDownload(path);
      expect(
        await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: path,
          senderId: 'bob',
        ),
        plain,
      );
      expect(remote.reads, 1);
    },
  );

  test(
    'storage exhaustion preserves existing files and reports commit failure',
        () async {
      await local.put(
        uid: 'alice',
        path: path,
        direction: ChatMediaDirection.received,
        ciphertext: remote.ciphertext,
      );
      backend.full = true;
      await expectLater(
        loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: '$path.other',
          senderId: 'bob',
        ),
        throwsA(
          isA<ChatLocalMediaException>().having(
                (error) => error.code,
            'code',
            'local_media_storage_full',
          ),
        ),
      );
      expect(await backend.file(path).readAsBytes(), remote.ciphertext);
      expect(loader.cached('$path.other'), isNull);
    },
  );

  for (final sender in ['alice', 'bob']) {
    test(
      'GCM failure for $sender preserves local-only sent repair policy',
          () async {
        final damaged = Uint8List.fromList(remote.ciphertext);
        damaged[damaged.length - 1] ^= 1;
        await local.put(
          uid: 'alice',
          path: path,
          direction: sender == 'alice'
              ? ChatMediaDirection.sent
              : ChatMediaDirection.received,
          ciphertext: damaged,
        );
        await expectLater(
          loader.fetchUncached(
            threadId: 'alice_bob',
            storagePath: path,
            senderId: sender,
          ),
          throwsA(
            isA<ChatLocalMediaException>().having(
                  (error) => error.code,
              'code',
              'local_media_corrupt',
            ),
          ),
        );
        expect(remote.reads, 0);
        await loader.retryFailedDownload(path);
        if (sender == 'alice') {
          expect(await backend.file(path).readAsBytes(), damaged);
          expect(remote.reads, 0);
        } else {
          expect(
            await loader.fetchUncached(
              threadId: 'alice_bob',
              storagePath: path,
              senderId: sender,
            ),
            plain,
          );
          expect(remote.reads, 1);
        }
      },
    );
  }

  test('vault move marker prevents automatic resurrection', () async {
    await local.put(
      uid: 'alice',
      path: path,
      direction: ChatMediaDirection.received,
      ciphertext: remote.ciphertext,
    );
    await loader.removeAfterVaultMove(path);
    await expectLater(
      loader.fetchUncached(
        threadId: 'alice_bob',
        storagePath: path,
        senderId: 'bob',
      ),
      throwsA(
        isA<ChatLocalMediaException>().having(
              (error) => error.code,
          'code',
          'local_media_moved',
        ),
      ),
    );
    expect(remote.reads, 0);
    expect(await backend.file(path).exists(), isFalse);
  });
}
