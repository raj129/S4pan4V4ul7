import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_downloads.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_cache.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_loader.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';

class _Media implements MediaRepository {
  int downloads = 0;
  Future<Uint8List> Function()? response;
  @override
  Future<Uint8List> downloadEncryptedMedia(String path) async {
    downloads++;
    return response == null ? Uint8List.fromList([1, 2]) : response!();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Crypto implements ChatCryptoService {
  @override
  Future<Uint8List> decryptMedia({
    required String threadId,
    required Uint8List encryptedBytes,
  }) async {
    if (encryptedBytes.first == 0) throw SecretBoxAuthenticationError();
    return Uint8List.fromList(encryptedBytes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ChatMediaCache disk;
  late _Media media;
  late ChatMediaLoader loader;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('chat_loader');
    disk = ChatMediaCache(directory: directory);
    media = _Media();
    loader = ChatMediaLoader(
      mediaRepository: media,
      cryptoService: _Crypto(),
      diskCache: disk,
      accountId: 'alice',
      loadTimeout: const Duration(seconds: 2),
    );
  });
  tearDown(() async {
    loader.dispose();
    await directory.delete(recursive: true);
  });

  test(
    'coalesces simultaneous downloads and notifies seeded consumers',
    () async {
      var notifications = 0;
      loader.addListener(() => notifications++);
      final first = loader.load(threadId: 't', storagePath: 'p');
      final second = loader.load(threadId: 't', storagePath: 'p');
      expect(identical(first, second), isFalse);
      expect(await first, [1, 2]);
      final firstBytes = await first;
      final secondBytes = await second;
      firstBytes.fillRange(0, firstBytes.length, 0);
      expect(secondBytes, [1, 2]);
      expect(media.downloads, 1);
      expect(notifications, 1);
      loader.seed('p', Uint8List.fromList([4]));
      expect(loader.cached('p'), [4]);
      expect(notifications, 2);
    },
  );

  test('times out and permits retry without navigating', () async {
    media.response = () => Completer<Uint8List>().future;
    await expectLater(
      loader.load(threadId: 't', storagePath: 'p'),
      throwsA(isA<TimeoutException>()),
    );
    media.response = () async => Uint8List.fromList([9]);
    expect(await loader.load(threadId: 't', storagePath: 'p'), [9]);
  });

  test('rejects late plaintext publication after account changes', () async {
    final pending = Completer<Uint8List>();
    media.response = () => pending.future;
    final old = loader.load(threadId: 't', storagePath: 'p');
    final assertion = expectLater(old, throwsA(isA<ChatMediaLoadCancelled>()));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    loader.setAccount('bob');
    pending.complete(Uint8List.fromList([1]));
    await assertion;
    expect(loader.cached('p'), isNull);
    expect(await disk.read('alice:p'), isNull);
  });

  test(
    'invalid cached ciphertext is replaced by one authenticated fetch',
    () async {
      await disk.write('alice:p', Uint8List.fromList([0]));
      expect(await loader.load(threadId: 't', storagePath: 'p'), [1, 2]);
      expect(media.downloads, 1);
      expect(await disk.read('alice:p'), [1, 2]);
    },
  );

  test('memory budget evicts least-recently-used entries', () {
    loader.dispose();
    loader = ChatMediaLoader(
      mediaRepository: media,
      cryptoService: _Crypto(),
      diskCache: disk,
      maxMemoryBytes: 4,
    );
    loader.seed('a', Uint8List.fromList([1, 2]));
    loader.seed('b', Uint8List.fromList([3, 4]));
    loader.cached('a');
    loader.seed('c', Uint8List.fromList([5, 6]));
    expect(loader.cached('b'), isNull);
    expect(loader.cached('a'), [1, 2]);
  });

  test(
    'vault move removes cache and suppresses persistent re-download',
    () async {
      await loader.load(threadId: 't', storagePath: 'p');
      await loader.removeAfterVaultMove('p');
      expect(await disk.wasMoved('alice:p'), isTrue);
      expect(await disk.read('alice:p'), isNull);
      expect(loader.cached('p'), isNull);
      await loader.fetchUncached(threadId: 't', storagePath: 'p');
      expect(await disk.read('alice:p'), isNull);
    },
  );

  group('Android durable acquisitions', () {
    const channel = MethodChannel('test/loader_downloads');
    late AndroidChatDownloads downloads;
    late List<String> calls;
    var state = 'completed';
    Uint8List payload = Uint8List.fromList([1, 2]);
    setUp(() {
      calls = [];
      state = 'completed';
      payload = Uint8List.fromList([1, 2]);
      downloads = AndroidChatDownloads(
        currentUid: () => loader.accountId,
        channel: channel,
        pollInterval: const Duration(milliseconds: 5),
      );
      loader.dispose();
      loader = ChatMediaLoader(
        mediaRepository: media,
        cryptoService: _Crypto(),
        diskCache: disk,
        accountId: 'alice',
        downloads: downloads,
        loadTimeout: const Duration(milliseconds: 10),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            if (call.method == 'list') {
              return [
                {
                  'uid': 'alice',
                  'threadId': 'alice_bob',
                  'storagePath': 'p',
                  'state': state,
                  'processedBytes': payload.length,
                  'totalBytes': payload.length,
                },
              ];
            }
            if (call.method == 'read') return payload;
            if (call.method == 'resume') state = 'completed';
            if (call.method == 'cancel') state = 'cancelled';
            return null;
          });
    });
    tearDown(() {
      downloads.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    test(
      'paused download is not aborted by the old whole-file timeout',
      () async {
        state = 'paused';
        final result = loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: 'p',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(calls, isNot(contains('read')));
        await downloads.command('p', 'resume');
        expect(await result, [1, 2]);
        expect(media.downloads, 0);
        expect(calls, contains('acknowledge'));
        expect(await disk.read('alice:p'), [1, 2]);
      },
    );
    test(
      'warm cache avoids native network work and returns owned plaintext',
      () async {
        final first = await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: 'p',
        );
        first.fillRange(0, first.length, 0);
        final second = await loader.fetchUncached(
          threadId: 'alice_bob',
          storagePath: 'p',
        );
        expect(second, [1, 2]);
        expect(calls.where((c) => c == 'enqueue'), hasLength(1));
        expect(calls.where((c) => c == 'read'), hasLength(1));
      },
    );
    test(
      'unauthenticated download is cancelled and never cached or acknowledged',
      () async {
        payload = Uint8List.fromList([0]);
        await expectLater(
          loader.fetchUncached(threadId: 'alice_bob', storagePath: 'p'),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
        expect(calls, contains('cancel'));
        expect(calls, isNot(contains('acknowledge')));
        expect(await disk.read('alice:p'), isNull);
      },
    );
  });
}
