import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/presentation/state/chat/media_send_status.dart';
import 'package:photo_vault/presentation/widgets/chat/attachment_upload_progress.dart';

void main() {
  Future<void> show(
    WidgetTester tester,
    MediaUploadLifecycle state, {
    Future<void> Function()? pause,
    VoidCallback? resume,
    VoidCallback? retry,
    VoidCallback? cancel,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AttachmentUploadProgress(
          status: MediaSendStatus(
            phase: MediaSendPhase.uploading,
            lifecycle: state,
            progress: .25,
            processedBytes: 256,
            totalBytes: 1024,
          ),
          onPause: pause,
          onResume: resume,
          onRetry: retry,
          onCancel: cancel,
        ),
      ),
    ),
  );

  testWidgets('single component reports bytes percent and state', (
    tester,
  ) async {
    await show(tester, MediaUploadLifecycle.uploading);
    expect(find.text('256 B / 1.0 KB · 25%'), findsOneWidget);
    expect(find.text('Uploading…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Resume'), findsNothing);
    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('paused and failed states expose only appropriate recovery', (
    tester,
  ) async {
    var resumes = 0;
    var retries = 0;
    await show(tester, MediaUploadLifecycle.paused, resume: () => resumes++);
    await tester.tap(find.text('Resume'));
    await tester.pump();
    expect(resumes, 1);
    expect(find.text('Pause'), findsNothing);
    await show(tester, MediaUploadLifecycle.failed, retry: () => retries++);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(retries, 1);
    expect(find.text('Resume'), findsNothing);
  });

  testWidgets('commands are serialized while native action is pending', (
    tester,
  ) async {
    final completion = Completer<void>();
    var actions = 0;
    await show(
      tester,
      MediaUploadLifecycle.uploading,
      pause: () {
        actions++;
        return completion.future;
      },
    );
    await tester.tap(find.text('Pause'));
    await tester.pump();
    await tester.tap(find.text('Pause'));
    expect(actions, 1);
    completion.complete();
    await tester.pump();
  });

  testWidgets('terminal states do not expose cancellation or spin', (
    tester,
  ) async {
    await show(tester, MediaUploadLifecycle.completed);
    expect(find.text('Cancel'), findsNothing);
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      .25,
    );
  });
}
