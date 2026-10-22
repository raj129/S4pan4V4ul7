import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/app/android_chat_viewer_guard.dart';

void main() {
  test(
    'native viewer exempts only window-focus loss, not actual backgrounding',
    () async {
      final closed = Completer<void>();
      final viewing = AndroidChatViewerGuard.run(() => closed.future);
      expect(
        AndroidChatViewerGuard.suppressesLock(AppLifecycleState.inactive),
        isTrue,
      );
      for (final state in [
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.detached,
        AppLifecycleState.resumed,
      ]) {
        expect(AndroidChatViewerGuard.suppressesLock(state), isFalse);
      }
      closed.complete();
      await viewing;
      expect(
        AndroidChatViewerGuard.suppressesLock(AppLifecycleState.inactive),
        isFalse,
      );
    },
  );

  test(
    'failure releases exemption and overlapping viewers are reference-counted',
    () async {
      final closed = Completer<void>();
      final first = AndroidChatViewerGuard.run(() => closed.future);
      await expectLater(
        AndroidChatViewerGuard.run<void>(
          () async => throw StateError('codec failed'),
        ),
        throwsStateError,
      );
      expect(
        AndroidChatViewerGuard.suppressesLock(AppLifecycleState.inactive),
        isTrue,
      );
      closed.complete();
      await first;
      expect(
        AndroidChatViewerGuard.suppressesLock(AppLifecycleState.inactive),
        isFalse,
      );
    },
  );
}
