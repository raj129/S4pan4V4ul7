import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/message_metadata.dart';

void main() {
  for (final type in [MessageType.gif, MessageType.sticker]) {
    test('$type survives Firestore serialization', () {
      final message = ChatMessage(
        messageId: 'message-id',
        threadId: 'thread-id',
        senderId: 'sender-id',
        encryptedText: 'ciphertext',
        sentAt: DateTime.utc(2026),
        deletedFor: const [],
        mediaRef: 'chat_media/thread-id/message-id/media.enc',
        mediaType: type,
        mediaMeta: const MediaMeta(sizeBytes: 128),
      );

      final restored = ChatMessage.fromFirestore(message.toFirestore());

      expect(restored.mediaType, type);
      expect(restored.mediaRef, message.mediaRef);
      expect(
        ChatMessage.mediaPreviewFor(type),
        type == MessageType.gif ? 'GIF' : 'Sticker',
      );
    });
  }
}
