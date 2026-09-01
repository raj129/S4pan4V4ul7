import 'package:equatable/equatable.dart';

import 'message_metadata.dart';
import 'message_reply.dart';

enum MessageType { text, image, video, file }

enum DeleteScope { forMe, forEveryone }

class ChatMessage extends Equatable {
  const ChatMessage({
    required this.messageId,
    required this.threadId,
    required this.senderId,
    required this.encryptedText,
    required this.sentAt,
    required this.deletedFor,
    this.mediaRef,
    this.mediaType,
    this.mediaMeta,
    this.encryptedMediaKey,
    this.localDecryptedText,
    this.replyTo,
    this.reactions = const {},
    this.readBy = const [],
    this.deletedForEveryone = false,
    this.editedAt,
    this.isForwarded = false,
    this.status,
  });

  final String messageId;
  final String threadId;
  final String senderId;

  /// Base64-encoded AES-GCM ciphertext (nonce prepended).
  final String encryptedText;

  /// Firebase Storage path for encrypted media blob (nullable for text-only).
  final String? mediaRef;
  final MessageType? mediaType;

  /// Clear-text layout hints (dimensions, size, duration) for the attachment.
  final MediaMeta? mediaMeta;

  /// Base64-encoded AES-GCM encrypted per-media key (optional future use).
  final String? encryptedMediaKey;

  /// Transient: decrypted plaintext populated in-memory after decryption.
  /// Never persisted to Firestore.
  final String? localDecryptedText;

  /// Set when this message is a reply, carrying a quote of the original.
  final MessageReply? replyTo;

  /// Emoji reactions as uid → emoji. One reaction per user, like WhatsApp.
  final Map<String, String> reactions;

  /// UIDs that have read this message, used to drive the read receipt ticks.
  final List<String> readBy;

  /// Tombstone flag. The document is kept so both sides render
  /// "This message was deleted" instead of the message silently vanishing.
  final bool deletedForEveryone;

  /// Set when the sender edited the text after sending.
  final DateTime? editedAt;

  /// True when this message was forwarded from another conversation, so the
  /// bubble can label it rather than passing it off as original.
  final bool isForwarded;

  /// Delivery state. Persisted only for terminal states; `sending`/`failed`
  /// are supplied locally by the outbox.
  final MessageStatus? status;

  final DateTime sentAt;

  /// UIDs of users who have deleted this message for themselves.
  final List<String> deletedFor;

  bool isDeletedFor(String uid) =>
      deletedForEveryone || deletedFor.contains(uid);

  bool get isMedia => mediaRef != null;

  bool get isEdited => editedAt != null;

  bool get isReply => replyTo != null;

  bool isReadBy(String uid) => readBy.contains(uid);

  /// True when the body is nothing but emoji, which renders oversized and
  /// without a bubble background, as in WhatsApp.
  bool get isEmojiOnly {
    final text = localDecryptedText?.trim();
    if (text == null || text.isEmpty || isMedia) return false;
    if (text.runes.length > 8) return false;
    return !RegExp(r'[0-9\p{L}]', unicode: true).hasMatch(text);
  }

  ChatMessage copyWith({
    String? encryptedText,
    String? localDecryptedText,
    MessageReply? replyTo,
    Map<String, String>? reactions,
    List<String>? readBy,
    List<String>? deletedFor,
    bool? deletedForEveryone,
    DateTime? editedAt,
    bool? isForwarded,
    MessageStatus? status,
    String? mediaRef,
    MessageType? mediaType,
    MediaMeta? mediaMeta,
  }) {
    return ChatMessage(
      messageId: messageId,
      threadId: threadId,
      senderId: senderId,
      encryptedText: encryptedText ?? this.encryptedText,
      sentAt: sentAt,
      deletedFor: deletedFor ?? this.deletedFor,
      mediaRef: mediaRef ?? this.mediaRef,
      mediaType: mediaType ?? this.mediaType,
      mediaMeta: mediaMeta ?? this.mediaMeta,
      encryptedMediaKey: encryptedMediaKey,
      localDecryptedText: localDecryptedText ?? this.localDecryptedText,
      replyTo: replyTo ?? this.replyTo,
      reactions: reactions ?? this.reactions,
      readBy: readBy ?? this.readBy,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      editedAt: editedAt ?? this.editedAt,
      isForwarded: isForwarded ?? this.isForwarded,
      status: status ?? this.status,
    );
  }

  ChatMessage withDecryptedText(String plaintext) =>
      copyWith(localDecryptedText: plaintext);

  Map<String, dynamic> toFirestore() => {
        'messageId': messageId,
        'threadId': threadId,
        'senderId': senderId,
        'encryptedText': encryptedText,
        'sentAt': sentAt.toUtc().millisecondsSinceEpoch,
        'deletedFor': deletedFor,
        'deletedForEveryone': deletedForEveryone,
        'reactions': reactions,
        'readBy': readBy,
        if (mediaRef != null) 'mediaRef': mediaRef,
        if (mediaType != null) 'mediaType': mediaType!.name,
        if (mediaMeta != null) 'mediaMeta': mediaMeta!.toFirestore(),
        if (encryptedMediaKey != null) 'encryptedMediaKey': encryptedMediaKey,
        if (replyTo != null) 'replyTo': replyTo!.toFirestore(),
        if (editedAt != null)
          'editedAt': editedAt!.toUtc().millisecondsSinceEpoch,
        if (isForwarded) 'isForwarded': true,
      };

  factory ChatMessage.fromFirestore(Map<String, dynamic> data) => ChatMessage(
        messageId: data['messageId'] as String,
        threadId: data['threadId'] as String,
        senderId: data['senderId'] as String,
        encryptedText: data['encryptedText'] as String? ?? '',
        sentAt: _timestamp(data['sentAt']) ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        deletedFor: List<String>.from(data['deletedFor'] as List? ?? const []),
        deletedForEveryone: data['deletedForEveryone'] as bool? ?? false,
        readBy: List<String>.from(data['readBy'] as List? ?? const []),
        reactions: (data['reactions'] as Map?)?.map(
              (k, v) => MapEntry(k as String, v as String),
            ) ??
            const {},
        mediaRef: data['mediaRef'] as String?,
        mediaType: _parseMediaType(data['mediaType'] as String?),
        mediaMeta: MediaMeta.fromFirestore(
          (data['mediaMeta'] as Map?)?.cast<String, dynamic>(),
        ),
        encryptedMediaKey: data['encryptedMediaKey'] as String?,
        replyTo: MessageReply.fromFirestore(
          (data['replyTo'] as Map?)?.cast<String, dynamic>(),
        ),
        editedAt: _timestamp(data['editedAt']),
        isForwarded: data['isForwarded'] as bool? ?? false,
      );

  /// Reads a millisecond epoch written by [toFirestore].
  static DateTime? _timestamp(Object? value) {
    if (value is num) {
      return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
    }
    return null;
  }

  /// Tolerates media types written by newer app versions.
  static MessageType? _parseMediaType(String? name) {
    if (name == null) return null;
    for (final type in MessageType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  @override
  List<Object?> get props => [
        messageId,
        threadId,
        senderId,
        encryptedText,
        localDecryptedText,
        sentAt,
        deletedFor,
        deletedForEveryone,
        mediaRef,
        mediaType,
        mediaMeta,
        replyTo,
        reactions,
        readBy,
        editedAt,
        status,
      ];
}
