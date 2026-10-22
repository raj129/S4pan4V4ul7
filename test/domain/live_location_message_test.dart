import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';

void main() {
  test('persists the live-location session reference on the chat marker', () {
    final message = ChatMessage(
      messageId: 'message-1',
      threadId: 'alice_bob',
      senderId: 'alice',
      encryptedText: 'ciphertext',
      sentAt: DateTime.utc(2026, 10, 21, 12),
      deletedFor: const [],
      mediaType: MessageType.liveLocation,
      liveLocationSessionId: 'session-1',
    );

    final restored = ChatMessage.fromFirestore(message.toFirestore());

    expect(restored.mediaType, MessageType.liveLocation);
    expect(restored.liveLocationSessionId, 'session-1');
    expect(restored.mediaPreview, 'Live location');
  });
}
