import 'package:equatable/equatable.dart';

import 'chat_message.dart';
import 'message_metadata.dart';

enum ChatMediaCategory { all, photos, videos, audio, documents }

enum ChatMediaSortOrder {
  sizeDescending,
  sizeAscending,
  dateDescending,
  dateAscending,
}

/// Represents an aggregated media item from chat messages.
class ChatMediaItem extends Equatable {
  const ChatMediaItem({
    required this.message,
    required this.category,
    required this.sizeBytes,
    this.cachedBytes = 0,
    this.displayName,
  });

  final ChatMessage message;
  final ChatMediaCategory category;
  final int sizeBytes;
  final int cachedBytes;
  final String? displayName;

  String get messageId => message.messageId;
  String get threadId => message.threadId;
  String? get mediaRef => message.mediaRef;
  String? get thumbRef => message.mediaMeta?.thumbRef;
  MessageType? get mediaType => message.mediaType;
  DateTime get sentAt => message.sentAt;
  MediaMeta? get mediaMeta => message.mediaMeta;

  String get readableSize {
    final bytes = sizeBytes;
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static ChatMediaCategory categorize(MessageType? type) {
    return switch (type) {
      MessageType.image ||
      MessageType.gif ||
      MessageType.sticker => ChatMediaCategory.photos,
      MessageType.video => ChatMediaCategory.videos,
      MessageType.audio => ChatMediaCategory.audio,
      MessageType.file => ChatMediaCategory.documents,
      _ => ChatMediaCategory.all,
    };
  }

  factory ChatMediaItem.fromMessage(
    ChatMessage message, {
    int cachedBytes = 0,
  }) {
    final category = categorize(message.mediaType);
    final size = message.mediaMeta?.sizeBytes ?? 0;
    String? name = message.mediaMeta?.filename;
    if (name == null || name.isEmpty) {
      if (message.isDocument) {
        name = message.documentName ?? 'Document';
      } else if (category == ChatMediaCategory.photos) {
        name = 'Photo';
      } else if (category == ChatMediaCategory.videos) {
        name = 'Video';
      } else if (category == ChatMediaCategory.audio) {
        name = 'Audio';
      } else {
        name = 'Attachment';
      }
    }

    return ChatMediaItem(
      message: message,
      category: category,
      sizeBytes: size,
      cachedBytes: cachedBytes,
      displayName: name,
    );
  }

  @override
  List<Object?> get props => [
    message,
    category,
    sizeBytes,
    cachedBytes,
    displayName,
  ];
}
