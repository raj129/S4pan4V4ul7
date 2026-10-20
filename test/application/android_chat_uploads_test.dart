import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_uploads.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/application/media/media_send_status.dart';

Map<String, Object?> _job({String uid = 'alice', String state = 'queued'}) => {
  'messageId': 'stable-id',
  'threadId': 'alice_bob',
  'senderId': uid,
  'encryptedText': 'authenticated-ciphertext',
  'sentAt': 1000,
  'mediaType': 'file',
  'mediaRef': 'chat_media/alice_bob/stable-id/media.enc',
  'state': state,
  'processedBytes': 250,
  'totalBytes': 1000,
  'isForwarded': true,
  'mediaMeta': {'sizeBytes': 972},
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/chat_uploads');
  late AndroidChatUploads uploads;
  final calls = <MethodCall>[];
  var nativeJobs = <Map<String, Object?>>[];

  setUp(() {
    calls.clear();
    nativeJobs = [_job()];
    uploads = AndroidChatUploads(channel: channel);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'list') return nativeJobs;
          if (call.method == 'cancel') return _job(state: 'cancelled');
          return null;
        });
  });

  tearDown(() {
    uploads.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'cancellation refuses to claim success while delivery commits',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => _job(state: 'uploading'),
          );
      await expectLater(uploads.cancel('stable-id'), throwsStateError);
    },
  );

  test(
    'parses every lifecycle and byte progress, retaining forwarded identity',
    () {
      for (final state in MediaUploadLifecycle.values) {
        final job = AndroidUploadJob.fromMap(_job(state: state.name));
        expect(job.status.lifecycle, state);
        expect(job.status.progress, .25);
        expect(job.status.processedBytes, 250);
        expect(job.status.totalBytes, 1000);
        expect(job.message.messageId, 'stable-id');
        expect(job.message.isForwarded, isTrue);
        expect(job.message.mediaType, MessageType.file);
      }
    },
  );

  test(
    'startup recovers only the signed-in account and wakes durable work',
    () async {
      nativeJobs.add(_job(uid: 'different-account'));
      final change = uploads.changes.first;
      uploads.start('alice');
      final recovered = await change;
      expect(recovered, hasLength(1));
      expect(recovered.single.message.senderId, 'alice');
      expect(calls.any((call) => call.method == 'wake'), isTrue);
      uploads.stop();
      expect(uploads.jobs, isEmpty);
    },
  );

  test('malformed journal records fail explicitly without inventing jobs', () {
    for (final change in [
      {'state': 'unknown'},
      {'totalBytes': -1},
      {'processedBytes': double.nan},
      {
        'mediaMeta': {'width': 'invalid'},
      },
      {'sentAt': 8640000000000001},
    ]) {
      expect(
        () => AndroidUploadJob.fromMap({..._job(), ...change}),
        throwsA(isA<FormatException>()),
      );
    }
  });

  test(
    'legacy finalized uploads hand off without reuploading a payload',
    () async {
      await uploads.recoverUploaded(
        AndroidUploadJob.fromMap(_job()).message,
        'bob',
      );
      expect(calls.single.method, 'recoverUploaded');
      expect(calls.single.arguments['mediaRef'], isNotNull);
      expect((calls.single.arguments as Map).containsKey('bytes'), isFalse);
    },
  );

  test(
    'controls delegate stable IDs rather than creating a second queue',
    () async {
      await uploads.pause('stable-id');
      await uploads.resume('stable-id');
      await uploads.cancel('stable-id');
      await uploads.retry('stable-id');
      expect(calls.map((call) => call.method), [
        'pause',
        'resume',
        'cancel',
        'retry',
      ]);
      expect(
        calls.every((call) => call.arguments['messageId'] == 'stable-id'),
        isTrue,
      );
    },
  );

  test(
    'queue acceptance sends ciphertext and metadata, never a plaintext path',
    () async {
      final ciphertext = Uint8List.fromList(List.filled(32, 7));
      await uploads.enqueue(
        message: ChatMessage(
          messageId: 'stable-id',
          threadId: 'alice_bob',
          senderId: 'alice',
          encryptedText: 'sealed-text',
          sentAt: DateTime.utc(2026),
          deletedFor: const [],
          mediaType: MessageType.file,
          isForwarded: true,
        ),
        recipientUid: 'bob',
        ciphertext: ciphertext,
      );
      final args = calls.single.arguments as Map;
      expect(args['bytes'], ciphertext);
      expect(args['isForwarded'], isTrue);
      expect(args.keys, isNot(contains('path')));
      expect(args.keys, isNot(contains('plaintext')));
    },
  );

  test('failed native control propagates to the caller', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (_) async => throw PlatformException(code: 'upload_unavailable'),
        );
    await expectLater(
      uploads.pause('stable-id'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('sign-out fences a late journal response', () async {
    final delayed = Completer<List<Map<String, Object?>>>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          channel,
          (call) async => call.method == 'list' ? delayed.future : null,
        );
    uploads.start('alice');
    await Future<void>.delayed(Duration.zero);
    uploads.stop();
    delayed.complete([_job()]);
    await Future<void>.delayed(Duration.zero);
    expect(uploads.jobs, isEmpty);
  });
}
