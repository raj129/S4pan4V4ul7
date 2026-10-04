import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/android_chat_secure_media_service.dart';
import 'package:photo_vault/presentation/widgets/chat/chat_audio_recorder.dart';

class _Recorder extends AndroidChatSecureMediaService {
  final calls = <String>[];
  bool deny = false;
  bool failCancel = false;
  String status = 'recording';
  final bytes = Uint8List.fromList([1, 2, 3]);
  @override
  Future<void> startRecording() async {
    calls.add('start');
    if (deny) throw PlatformException(code: 'permission_denied');
  }

  @override
  Future<void> pauseRecording() async => calls.add('pause');
  @override
  Future<void> resumeRecording() async => calls.add('resume');
  @override
  Future<void> cancelRecording() async {
    calls.add('cancel');
    if (failCancel) throw StateError('native cleanup failed');
  }

  @override
  Future<String> recordingStatus() async => status;
  @override
  Future<SecureMediaAttachment> stopRecording() async {
    calls.add('stop');
    return SecureMediaAttachment(
      bytes: bytes,
      fileName: 'recording.wav',
      mimeType: 'audio/wav',
    );
  }
}

void main() {
  testWidgets(
    'larger labeled recorder pauses resumes and dismisses on queue acceptance',
    (tester) async {
      final recorder = _Recorder();
      var dismissed = 0;
      var accepted = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatAudioRecorder(
              service: recorder,
              onDismiss: () => dismissed++,
              onError: (_) {},
              onRecorded: (_) async => accepted++,
            ),
          ),
        ),
      );
      expect(find.text('Start'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump();
      await tester.tap(find.text('Pause'));
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Paused. Elapsed recording time 0:00.',
        ),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('0:00'), findsOneWidget);
      await tester.tap(find.text('Resume'));
      await tester.pump();
      await tester.tap(find.text('Stop and send'));
      await tester.pump();
      expect(recorder.calls, ['start', 'pause', 'resume', 'stop']);
      expect(accepted, 1);
      expect(dismissed, 1);
      expect(recorder.bytes, [0, 0, 0]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('cancellation closes panel without sending', (tester) async {
    final recorder = _Recorder();
    var dismissed = 0;
    var sent = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAudioRecorder(
            service: recorder,
            onDismiss: () => dismissed++,
            onError: (_) {},
            onRecorded: (_) async => sent++,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(dismissed, 1);
    expect(sent, 0);
    expect(recorder.calls, ['cancel']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('cancel cleanup failure is surfaced before closing', (
    tester,
  ) async {
    final recorder = _Recorder()..failCancel = true;
    final errors = <String>[];
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAudioRecorder(
            service: recorder,
            onDismiss: () => dismissed++,
            onError: errors.add,
            onRecorded: (_) async => fail('Cancelled recordings must not send'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(dismissed, 1);
    expect(errors.single, contains('native cleanup failed'));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('permission failure dismisses and surfaces the error', (
    tester,
  ) async {
    final recorder = _Recorder()..deny = true;
    final errors = <String>[];
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAudioRecorder(
            service: recorder,
            onDismiss: () => dismissed++,
            onError: errors.add,
            onRecorded: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    expect(errors, hasLength(1));
    expect(dismissed, 1);
    expect(recorder.calls, ['start', 'cancel']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('microphone failure while paused closes panel', (tester) async {
    final recorder = _Recorder();
    var dismissed = 0;
    final errors = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAudioRecorder(
            service: recorder,
            onDismiss: () => dismissed++,
            onError: errors.add,
            onRecorded: (_) async {},
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Pause'));
    await tester.pump();
    recorder.status = 'failed';
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(dismissed, 1);
    expect(errors, hasLength(1));
    expect(recorder.calls.last, 'cancel');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('panel waits for durable acceptance and closes on failure', (
    tester,
  ) async {
    final recorder = _Recorder();
    final acceptance = Completer<void>();
    var dismissed = 0;
    final errors = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAudioRecorder(
            service: recorder,
            onDismiss: () => dismissed++,
            onError: errors.add,
            onRecorded: (_) => acceptance.future,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.tap(find.text('Stop and send'));
    await tester.pump();
    expect(dismissed, 0);
    acceptance.completeError(StateError('Encrypted staging storage is full'));
    await tester.pump();
    expect(dismissed, 1);
    expect(errors.single, contains('storage is full'));
    expect(recorder.bytes, [0, 0, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('backgrounding cancels recording without delivery', (
    tester,
  ) async {
    final recorder = _Recorder();
    var dismissed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAudioRecorder(
            service: recorder,
            onDismiss: () => dismissed++,
            onError: (_) {},
            onRecorded: (_) async => fail('Must not send abandoned recording'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(dismissed, 1);
    expect(recorder.calls.last, 'cancel');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('leaving chat cleans up and reports disposal cleanup failure', (
    tester,
  ) async {
    final recorder = _Recorder()..failCancel = true;
    final errors = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatAudioRecorder(
            service: recorder,
            onDismiss: () {},
            onError: errors.add,
            onRecorded: (_) async =>
                fail('An abandoned recording must not send'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Start'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(recorder.calls, ['start', 'cancel']);
    expect(errors.single, contains('native cleanup failed'));
  });
}
