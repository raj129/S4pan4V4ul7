import 'package:equatable/equatable.dart';

import 'chat_message.dart';

/// Layout and download hints for an encrypted media attachment.
///
/// These fields are stored in clear text because the UI needs them *before* the
/// blob is downloaded, in order to reserve the right amount of space and avoid
/// the list jumping around. They leak size and shape, never content.
class MediaMeta extends Equatable {
  const MediaMeta({
    this.width,
    this.height,
    this.sizeBytes,
    this.durationMs,
    this.filename,
  });

  final int? width;
  final int? height;
  final int? sizeBytes;

  /// Video duration in milliseconds.
  final int? durationMs;

  /// Original file name, shown for document attachments.
  final String? filename;

  /// Aspect ratio for the placeholder, falling back to 4:3 when unknown.
  double get aspectRatio {
    if (width == null || height == null || width == 0 || height == 0) {
      return 4 / 3;
    }
    return width! / height!;
  }

  String get readableSize {
    final bytes = sizeBytes;
    if (bytes == null) return '';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get readableDuration {
    final ms = durationMs;
    if (ms == null) return '';
    final total = Duration(milliseconds: ms);
    final minutes = total.inMinutes;
    final seconds = total.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toFirestore() => {
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (sizeBytes != null) 'sizeBytes': sizeBytes,
        if (durationMs != null) 'durationMs': durationMs,
        if (filename != null) 'filename': filename,
      };

  static MediaMeta? fromFirestore(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return null;
    return MediaMeta(
      width: (data['width'] as num?)?.toInt(),
      height: (data['height'] as num?)?.toInt(),
      sizeBytes: (data['sizeBytes'] as num?)?.toInt(),
      durationMs: (data['durationMs'] as num?)?.toInt(),
      filename: data['filename'] as String?,
    );
  }

  @override
  List<Object?> get props => [width, height, sizeBytes, durationMs, filename];
}

/// Delivery state of an outgoing message, rendered as ticks on the bubble.
///
/// [sending] and [failed] are local-only states produced by the outbox; they
/// are never written to Firestore.
enum MessageStatus { sending, sent, delivered, read, failed }

extension MessageStatusX on MessageStatus {
  bool get isPending => this == MessageStatus.sending;
  bool get isFailed => this == MessageStatus.failed;

  /// Resolves the tick state for a 1:1 thread from the recipient's read state.
  static MessageStatus forOneToOne({
    required bool readByRecipient,
    required bool recipientOnline,
  }) {
    if (readByRecipient) return MessageStatus.read;
    if (recipientOnline) return MessageStatus.delivered;
    return MessageStatus.sent;
  }

  /// Parses a persisted status name, tolerating unknown/legacy values.
  static MessageStatus? tryParse(String? name) {
    if (name == null) return null;
    for (final status in MessageStatus.values) {
      if (status.name == name) return status;
    }
    return null;
  }
}

/// Convenience view over the `reactions` map (uid → emoji).
extension MessageReactionsX on ChatMessage {
  /// Groups reactions into emoji → list of reacting uids, for the summary row.
  Map<String, List<String>> get groupedReactions {
    final grouped = <String, List<String>>{};
    reactions.forEach((uid, emoji) {
      grouped.putIfAbsent(emoji, () => <String>[]).add(uid);
    });
    return grouped;
  }

  /// The emoji [uid] reacted with, or null.
  String? reactionOf(String uid) => reactions[uid];
}
