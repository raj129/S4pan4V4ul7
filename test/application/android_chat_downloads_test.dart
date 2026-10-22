import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_downloads.dart';
import 'package:photo_vault/features/chat/application/media/media_send_status.dart';

class _ReadOnlyMethodCodec extends StandardMethodCodec {
  const _ReadOnlyMethodCodec();

  @override
  dynamic decodeEnvelope(ByteData envelope) {
    final value = super.decodeEnvelope(envelope);
    return value is Uint8List ? value.asUnmodifiableView() : value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/chat_downloads', _ReadOnlyMethodCodec());
  late AndroidChatDownloads downloads;
  late List<String> calls;
  var uid = 'alice';
  var state = 'completed';
  const path = 'chat_media/alice_bob/id/media.enc';
  setUp(() {
    uid = 'alice';
    state = 'completed';
    calls = [];
    downloads = AndroidChatDownloads(
      currentUid: () => uid,
      channel: channel,
      pollInterval: const Duration(milliseconds: 5),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'list') {
        return [
          {
            'uid': uid,
            'threadId': 'alice_bob',
            'storagePath': path,
            'state': state,
            'processedBytes': 3,
            'totalBytes': 3,
          },
        ];
      }
      if (call.method == 'read') return Uint8List.fromList([1, 2, 3]);
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
    'simultaneous consumers share acquisition but own separate buffers',
        () async {
      final first = downloads.acquire(
        uid: uid,
        threadId: 'alice_bob',
        storagePath: path,
      );
      final second = downloads.acquire(
        uid: uid,
        threadId: 'alice_bob',
        storagePath: path,
      );
      final buffers = await Future.wait([first, second]);
      expect(calls.where((c) => c == 'enqueue'), hasLength(1));
      expect(calls.where((c) => c == 'read'), hasLength(1));
      expect(buffers.first, [1, 2, 3]);
      buffers.first.fillRange(0, 3, 0);
      expect(buffers.last, [1, 2, 3]);
      expect(calls, isNot(contains('acknowledge')));
      await downloads.acknowledge(uid, path);
      expect(calls.last, 'acknowledge');
    },
  );

  test(
    'paused acquisition waits for explicit resume and retains progress',
        () async {
      state = 'paused';
      var resolved = false;
      final result = downloads.acquire(
        uid: uid,
        threadId: 'alice_bob',
        storagePath: path,
      )
        ..then((_) => resolved = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(resolved, isFalse);
      expect(downloads
          .job(path)
          ?.state, MediaUploadLifecycle.paused);
      expect(downloads
          .job(path)
          ?.processedBytes, 3);
      await downloads.command(path, 'resume');
      expect(await result, [1, 2, 3]);
    },
  );

  test('cancel ends waiting acquisition explicitly', () async {
    state = 'paused';
    final result = downloads.acquire(
      uid: uid,
      threadId: 'alice_bob',
      storagePath: path,
    );
    final assertion = expectLater(
      result,
      throwsA(isA<ChatDownloadCancelled>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await downloads.command(path, 'cancel');
    await assertion;
    expect(calls, isNot(contains('read')));
  });

  test('account change prevents publication', () async {
    state = 'queued';
    final result = downloads.acquire(
      uid: uid,
      threadId: 'alice_bob',
      storagePath: path,
    );
    final assertion = expectLater(
      result,
      throwsA(isA<ChatDownloadCancelled>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    uid = 'bob';
    downloads.clearAccount();
    await assertion;
    expect(downloads.job(path), isNull);
  });

  test('malformed offsets and states are rejected', () {
    expect(
          () =>
          AndroidDownloadJob.fromMap({
            'uid': 'alice',
            'threadId': 'alice_bob',
            'storagePath': path,
            'state': 'uploading',
            'processedBytes': 4,
            'totalBytes': 3,
          }),
      throwsFormatException,
    );
    expect(
          () =>
          AndroidDownloadJob.fromMap({
            'uid': 'alice',
            'threadId': 'alice_bob',
            'storagePath': path,
            'state': 'unknown',
            'processedBytes': 0,
            'totalBytes': 3,
          }),
      throwsFormatException,
    );
  });

  test('sent acquisition is rejected before enqueueing any download', () async {
    await expectLater(
      downloads.acquire(
        uid: uid,
        threadId: 'alice_bob',
        storagePath: path,
        senderId: uid,
      ),
      throwsA(isA<ChatDownloadFailed>()),
    );
    expect(calls, isEmpty);
  });

  test('an already completed sent copy is read without enqueueing', () async {
    expect(await downloads.readCompleted(uid, path), [1, 2, 3]);
    expect(calls, ['list', 'read']);
  });

  test(
    'clearing and reusing the same account fences previous acquisitions',
        () async {
      state = 'paused';
      final old = downloads.acquire(
        uid: uid,
        threadId: 'alice_bob',
        storagePath: path,
      );
      final cancelled = expectLater(old, throwsA(isA<ChatDownloadCancelled>()));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      downloads.clearAccount();
      state = 'completed';
      final fresh = downloads.acquire(
        uid: uid,
        threadId: 'alice_bob',
        storagePath: path,
      );
      await cancelled;
      expect(await fresh, [1, 2, 3]);
      expect(calls.where((call) => call == 'enqueue'), hasLength(2));
    },
  );
}
