import 'package:equatable/equatable.dart';

import 'chat_message.dart';

/// A denormalised snapshot of the message being replied to.
///
/// Stored on the *replying* message so the quoted header can render without a
/// second Firestore read, and so the quote survives the original being deleted.
/// The preview text is encrypted with the same thread key as any other message.
class MessageReply extends Equatable {
  const MessageReply({
    required this.messageId,
    required this.senderId,
    required this.encryptedPreview,
    this.mediaType,
    this.localDecryptedPreview,
  });

  /// ID of the original message, used to scroll to it on tap.
  final String messageId;

  /// Sender of the original message, used for the "You"/name label.
  final String senderId;

  /// Base64 AES-GCM ciphertext of a short snippet of the original.
  final String encryptedPreview;

  /// Set when the original was media, so the quote can show an icon.
  final MessageType? mediaType;

  /// Transient: populated in-memory after decryption. Never persisted.
  final String? localDecryptedPreview;

  MessageReply withDecryptedPreview(String plaintext) => MessageReply(
        messageId: messageId,
        senderId: senderId,
        encryptedPreview: encryptedPreview,
        mediaType: mediaType,
        localDecryptedPreview: plaintext,
      );

  Map<String, dynamic> toFirestore() => {
        'messageId': messageId,
        'senderId': senderId,
        'encryptedPreview': encryptedPreview,
        if (mediaType != null) 'mediaType': mediaType!.name,
      };

  static MessageReply? fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return null;
    final messageId = data['messageId'] as String?;
    final senderId = data['senderId'] as String?;
    if (messageId == null || senderId == null) return null;
    return MessageReply(
      messageId: messageId,
      senderId: senderId,
      encryptedPreview: data['encryptedPreview'] as String? ?? '',
      mediaType: _parseMediaType(data['mediaType'] as String?),
    );
  }

  static MessageType? _parseMediaType(String? name) {
    if (name == null) return null;
    for (final type in MessageType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  @override
  List<Object?> get props =>
      [messageId, senderId, encryptedPreview, mediaType, localDecryptedPreview];
}
