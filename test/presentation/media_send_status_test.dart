import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/presentation/state/chat/media_send_status.dart';

void main() {
  group('MediaUploadLifecycleTransitions', () {
    test('pause is durable and terminal states cannot restart', () {
      expect(
        MediaUploadLifecycle.uploading.canTransitionTo(
          MediaUploadLifecycle.paused,
        ),
        isTrue,
      );
      expect(
        MediaUploadLifecycle.paused.canTransitionTo(
          MediaUploadLifecycle.resumed,
        ),
        isTrue,
      );
      expect(
        MediaUploadLifecycle.completed.canTransitionTo(
          MediaUploadLifecycle.retrying,
        ),
        isFalse,
      );
      expect(
        MediaUploadLifecycle.cancelled.canTransitionTo(
          MediaUploadLifecycle.uploading,
        ),
        isFalse,
      );
    });

    test('failed jobs can retry, but cannot skip to uploading', () {
      expect(
        MediaUploadLifecycle.failed.canTransitionTo(
          MediaUploadLifecycle.retrying,
        ),
        isTrue,
      );
      expect(
        MediaUploadLifecycle.failed.canTransitionTo(
          MediaUploadLifecycle.uploading,
        ),
        isFalse,
      );
    });
  });

  test(
    'durable status exposes ciphertext byte progress and lifecycle label',
    () {
      const status = MediaSendStatus(
        phase: MediaSendPhase.uploading,
        progress: 0.5,
        lifecycle: MediaUploadLifecycle.uploading,
        processedBytes: 512,
        totalBytes: 1024,
      );

      expect(status.isIndeterminate, isFalse);
      expect(status.label, 'Uploading…');
      expect(status.processedBytes, 512);
      expect(status.totalBytes, 1024);
      expect(
        status.copyWith(lifecycle: MediaUploadLifecycle.paused).isIndeterminate,
        isFalse,
      );
    },
  );
}
