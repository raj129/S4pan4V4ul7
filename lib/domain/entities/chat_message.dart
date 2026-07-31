import 'package:equatable/equatable.dart';

enum MessageType { text, image, video }

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
    this.encryptedMediaKey,
    this.localDecryptedText,
  });

  final String messageId;
  final String threadId;
  final String senderId;

  /// Base64-encoded AES-GCM ciphertext (nonce prepended).
  final String encryptedText;

  /// Firebase Storage path for encrypted media blob (nullable for text-only).
  final String? mediaRef;
  final MessageType? mediaType;

  /// Base64-encoded AES-GCM encrypted per-media key (optional future use).
  final String? encryptedMediaKey;

  /// Transient: decrypted plaintext populated in-memory after decryption.
  /// Never persisted to Firestore.
  final String? localDecryptedText;

  final DateTime sentAt;

  /// UIDs of users who have deleted this message for themselves.
  final List<String> deletedFor;

  bool isDeletedFor(String uid) => deletedFor.contains(uid);

  bool get isMedia => mediaRef != null;

  ChatMessage withDecryptedText(String plaintext) => ChatMessage(
        messageId: messageId,
        threadId: threadId,
        senderId: senderId,
        encryptedText: encryptedText,
        sentAt: sentAt,
        deletedFor: deletedFor,
        mediaRef: mediaRef,
        mediaType: mediaType,
        encryptedMediaKey: encryptedMediaKey,
        localDecryptedText: plaintext,
      );

  Map<String, dynamic> toFirestore() => {
        'messageId': messageId,
        'threadId': threadId,
        'senderId': senderId,
        'encryptedText': encryptedText,
        'sentAt': sentAt.toUtc().millisecondsSinceEpoch,
        'deletedFor': deletedFor,
        if (mediaRef != null) 'mediaRef': mediaRef,
        if (mediaType != null) 'mediaType': mediaType!.name,
        if (encryptedMediaKey != null) 'encryptedMediaKey': encryptedMediaKey,
      };

  factory ChatMessage.fromFirestore(Map<String, dynamic> data) => ChatMessage(
        messageId: data['messageId'] as String,
        threadId: data['threadId'] as String,
        senderId: data['senderId'] as String,
        encryptedText: data['encryptedText'] as String,
        sentAt: DateTime.fromMillisecondsSinceEpoch(
          (data['sentAt'] as int?) ?? 0,
          isUtc: true,
        ),
        deletedFor: List<String>.from(data['deletedFor'] as List? ?? []),
        mediaRef: data['mediaRef'] as String?,
        mediaType: data['mediaType'] != null
            ? MessageType.values.byName(data['mediaType'] as String)
            : null,
        encryptedMediaKey: data['encryptedMediaKey'] as String?,
      );

  @override
  List<Object?> get props => [
        messageId,
        threadId,
        senderId,
        encryptedText,
        sentAt,
        deletedFor,
        mediaRef,
        mediaType,
      ];
}
