import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_vault/core/app/android_chat_viewer_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_secure_media_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/secure_media');
  const service = AndroidChatSecureMediaService(channel: channel);
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'recordingStatus') return 'paused';
          final attachment = {
            'bytes': Uint8List.fromList([1, 2, 3]),
            'fileName': 'recording.wav',
            'mimeType': 'audio/wav',
          };
          if (call.method == 'pickAttachments') return [attachment];
          if (call.method == 'stopRecording' ||
              call.method == 'capturePhoto' ||
              call.method == 'readContentUri') {
            return attachment;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('acquisition returns bytes without a staging path', () async {
    final attachments = await service.pickAttachments(
      mimeTypes: ['image/*', 'video/*'],
    );
    expect(attachments.single.bytes, [1, 2, 3]);
    expect(attachments.single.mimeType, 'audio/wav');
    expect(calls.single.method, 'pickAttachments');
    expect(calls.single.arguments, {
      'mimeTypes': ['image/*', 'video/*'],
    });
  });

  test('rejects filesystem acquisition and empty player input', () async {
    await expectLater(
      service.readContentUri('file:///plaintext.mp4'),
      throwsArgumentError,
    );
    expect(() => service.showVideo(Uint8List(0)), throwsArgumentError);
    expect(calls, isEmpty);
  });

  test(
    'recording returns typed in-memory WAV and supports cancellation',
    () async {
      expect(
        AndroidChatSecureMediaService.maxRecordingDuration,
        const Duration(minutes: 5),
      );
      await service.startRecording();
      await service.pauseRecording();
      await service.resumeRecording();
      expect(await service.recordingStatus(), 'paused');
      final recording = await service.stopRecording();
      await service.cancelRecording();
      expect(recording.fileName, 'recording.wav');
      expect(recording.bytes, [1, 2, 3]);
      expect(calls.map((call) => call.method), [
        'startRecording',
        'pauseRecording',
        'resumeRecording',
        'recordingStatus',
        'stopRecording',
        'cancelRecording',
      ]);
    },
  );

  test('players use only bounded byte buffers and close', () async {
    final bytes = Uint8List.fromList([4, 5]);
    await service.showVideo(bytes);
    await service.showAudio(bytes);
    await service.showPdf(bytes);
    await service.close();
    expect(calls.map((call) => call.method), [
      'showVideo',
      'showAudio',
      'showPdf',
      'close',
    ]);
    expect(calls.first.arguments, {'bytes': bytes, 'measureStartup': true});
  });

  test(
    'native playback keeps focus-only lock exemption until its dialog closes',
    () async {
      final closing = Completer<void>();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) => closing.future);
      final playback = service.showVideo(Uint8List.fromList([1]));
      expect(
        AndroidChatViewerGuard.suppressesLock(AppLifecycleState.inactive),
        isTrue,
      );
      expect(
        AndroidChatViewerGuard.suppressesLock(AppLifecycleState.paused),
        isFalse,
      );
      closing.complete();
      await playback;
      expect(
        AndroidChatViewerGuard.suppressesLock(AppLifecycleState.inactive),
        isFalse,
      );
    },
  );

  test('unsupported PDF and corrupt response propagate safely', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'showPdf') {
            throw PlatformException(
              code: 'unsupported',
              message: 'Secure PDF preview requires Android 8.',
            );
          }
          return {'bytes': Uint8List(0)};
        });
    await expectLater(
      service.showPdf(Uint8List.fromList([1])),
      throwsA(isA<PlatformException>()),
    );
    await expectLater(service.stopRecording(), throwsArgumentError);
  });

  test('invalid native recording states are surfaced', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'unknown');
    await expectLater(service.recordingStatus(), throwsStateError);
  });
}
