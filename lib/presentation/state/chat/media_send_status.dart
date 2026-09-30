import 'package:equatable/equatable.dart';

/// Which part of sending an attachment is currently running.
///
/// Sending is not one operation: a photo is compressed, encrypted, then
/// uploaded as two separate blobs. Compression is usually the slowest step and
/// reports no byte counts, so the phase is tracked separately from the
/// fraction — the UI can animate indeterminately where there is nothing to
/// measure instead of sitting frozen at zero.
enum MediaSendPhase { preparing, encrypting, uploading }

/// Progress of one outgoing attachment.
class MediaSendStatus extends Equatable {
  const MediaSendStatus({required this.phase, required this.progress});

  const MediaSendStatus.preparing()
    : phase = MediaSendPhase.preparing,
      progress = 0;

  final MediaSendPhase phase;

  /// Overall completion, 0..1, weighted across every phase — never restarted
  /// per phase, so the ring only ever moves forwards.
  final double progress;

  /// True while no meaningful fraction can be reported yet.
  bool get isIndeterminate =>
      phase != MediaSendPhase.uploading || progress <= 0;

  String get label => switch (phase) {
    MediaSendPhase.preparing => 'Preparing…',
    MediaSendPhase.encrypting => 'Encrypting…',
    MediaSendPhase.uploading => 'Uploading…',
  };

  MediaSendStatus copyWith({MediaSendPhase? phase, double? progress}) =>
      MediaSendStatus(
        phase: phase ?? this.phase,
        progress: progress ?? this.progress,
      );

  @override
  List<Object?> get props => [phase, progress];
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
