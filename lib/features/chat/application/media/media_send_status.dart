import 'package:equatable/equatable.dart';

/// Which part of sending an attachment is currently running.
///
/// Sending is not one operation: a photo is compressed, encrypted, then
/// uploaded as two separate blobs. Compression is usually the slowest step and
/// reports no byte counts, so the phase is tracked separately from the
/// fraction — the UI can animate indeterminately where there is nothing to
/// measure instead of sitting frozen at zero.
enum MediaSendPhase { preparing, encrypting, uploading }

/// Durable lifecycle owned by the Android upload journal.
enum MediaUploadLifecycle {
  queued,
  uploading,
  paused,
  completed,
  failed,
  cancelled,
  retrying,
  resumed,
}

extension MediaUploadLifecycleTransitions on MediaUploadLifecycle {
  bool canTransitionTo(MediaUploadLifecycle next) => switch (this) {
    MediaUploadLifecycle.queued =>
      next == MediaUploadLifecycle.uploading ||
          next == MediaUploadLifecycle.cancelled ||
          next == MediaUploadLifecycle.failed,
    MediaUploadLifecycle.uploading =>
      next == MediaUploadLifecycle.paused ||
          next == MediaUploadLifecycle.completed ||
          next == MediaUploadLifecycle.failed ||
          next == MediaUploadLifecycle.cancelled ||
          next == MediaUploadLifecycle.retrying,
    MediaUploadLifecycle.paused =>
      next == MediaUploadLifecycle.resumed ||
          next == MediaUploadLifecycle.cancelled,
    MediaUploadLifecycle.failed =>
      next == MediaUploadLifecycle.retrying ||
          next == MediaUploadLifecycle.cancelled,
    MediaUploadLifecycle.retrying =>
      next == MediaUploadLifecycle.resumed ||
          next == MediaUploadLifecycle.uploading ||
          next == MediaUploadLifecycle.paused ||
          next == MediaUploadLifecycle.failed ||
          next == MediaUploadLifecycle.cancelled,
    MediaUploadLifecycle.resumed =>
      next == MediaUploadLifecycle.uploading ||
          next == MediaUploadLifecycle.paused ||
          next == MediaUploadLifecycle.completed ||
          next == MediaUploadLifecycle.failed ||
          next == MediaUploadLifecycle.cancelled,
    MediaUploadLifecycle.completed || MediaUploadLifecycle.cancelled => false,
  };
}

/// Progress of one outgoing attachment.
class MediaSendStatus extends Equatable {
  const MediaSendStatus({
    required this.phase,
    required this.progress,
    this.lifecycle,
    this.processedBytes,
    this.totalBytes,
  });

  const MediaSendStatus.preparing()
    : phase = MediaSendPhase.preparing,
      progress = 0,
      lifecycle = null,
      processedBytes = null,
      totalBytes = null;

  final MediaSendPhase phase;

  /// Overall completion, 0..1, weighted across every phase — never restarted
  /// per phase, so the ring only ever moves forwards.
  final double progress;

  /// Durable upload state, populated for jobs reported by Android.
  final MediaUploadLifecycle? lifecycle;

  /// Ciphertext bytes reported by the native uploader.
  final int? processedBytes;

  /// Total ciphertext bytes, including any preview blob.
  final int? totalBytes;

  /// True while no meaningful fraction can be reported yet.
  bool get isIndeterminate {
    if (lifecycle == MediaUploadLifecycle.completed ||
        lifecycle == MediaUploadLifecycle.failed ||
        lifecycle == MediaUploadLifecycle.cancelled ||
        lifecycle == MediaUploadLifecycle.paused) {
      return false;
    }
    if (lifecycle != null && lifecycle != MediaUploadLifecycle.uploading) {
      return true;
    }
    return phase != MediaSendPhase.uploading || progress <= 0;
  }

  String get label {
    final state = lifecycle;
    if (state != null) {
      return switch (state) {
        MediaUploadLifecycle.queued => 'Queued',
        MediaUploadLifecycle.uploading => 'Uploading…',
        MediaUploadLifecycle.paused => 'Paused',
        MediaUploadLifecycle.completed => 'Sent',
        MediaUploadLifecycle.failed => 'Upload failed',
        MediaUploadLifecycle.cancelled => 'Cancelled',
        MediaUploadLifecycle.retrying => 'Retrying…',
        MediaUploadLifecycle.resumed => 'Resuming…',
      };
    }
    return switch (phase) {
      MediaSendPhase.preparing => 'Preparing…',
      MediaSendPhase.encrypting => 'Encrypting…',
      MediaSendPhase.uploading => 'Uploading…',
    };
  }

  MediaSendStatus copyWith({
    MediaSendPhase? phase,
    double? progress,
    MediaUploadLifecycle? lifecycle,
    int? processedBytes,
    int? totalBytes,
  }) => MediaSendStatus(
    phase: phase ?? this.phase,
    progress: progress ?? this.progress,
    lifecycle: lifecycle ?? this.lifecycle,
    processedBytes: processedBytes ?? this.processedBytes,
    totalBytes: totalBytes ?? this.totalBytes,
  );

  @override
  List<Object?> get props => [
    phase,
    progress,
    lifecycle,
    processedBytes,
    totalBytes,
  ];
}

/// How much of the overall bar each phase is worth.
///
/// Compression dominates the wall-clock time for a large photo, so it gets the
/// largest share; the thumbnail is tiny next to the full image.
abstract final class MediaSendWeights {
  /// End of compression / start of the thumbnail upload.
  static const compressEnd = 0.35;

  /// End of the thumbnail upload / start of the full upload.
  static const thumbEnd = 0.45;

  /// Maps a 0..1 fraction within a phase onto the overall bar.
  static double span(double start, double end, double fraction) {
    final clamped = fraction.isNaN ? 0.0 : fraction.clamp(0.0, 1.0);
    return start + (end - start) * clamped;
  }
}
