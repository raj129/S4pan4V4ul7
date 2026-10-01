import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/entities/message_metadata.dart';

ChatMessage _message({
  List<String> deliveredTo = const [],
  List<String> readBy = const [],
}) => ChatMessage(
  messageId: 'message-1',
  threadId: 'sender_recipient',
  senderId: 'sender',
  encryptedText: 'ciphertext',
  sentAt: DateTime.utc(2026, 1, 1),
  deletedFor: const [],
  deliveredTo: deliveredTo,
  readBy: readBy,
);

void main() {
  group('message status', () {
    test('online presence does not imply delivery', () {
      expect(
        MessageStatusX.forOneToOne(
          readByRecipient: false,
          deliveredToRecipient: false,
        ),
        MessageStatus.sent,
      );
    });

    test('recipient receipt advances to delivered', () {
      expect(
        MessageStatusX.forOneToOne(
          readByRecipient: false,
          deliveredToRecipient: true,
        ),
        MessageStatus.delivered,
      );
    });

    test('read receipt takes precedence over delivery', () {
      expect(
        MessageStatusX.forOneToOne(
          readByRecipient: true,
          deliveredToRecipient: false,
        ),
        MessageStatus.read,
      );
    });
  });

  group('delivery receipt persistence', () {
    test('round-trips delivered recipients', () {
      final original = _message(deliveredTo: const ['recipient']);
      final restored = ChatMessage.fromFirestore(original.toFirestore());

      expect(restored.deliveredTo, ['recipient']);
      expect(restored.copyWith(deliveredTo: ['second']).deliveredTo, [
        'second',
      ]);
    });

    test('older documents without receipt data remain compatible', () {
      final data = _message().toFirestore()..remove('deliveredTo');

      expect(ChatMessage.fromFirestore(data).deliveredTo, isEmpty);
    });

    test('pending local Firestore writes remain in sending state', () {
      final data = _message().toFirestore();

      expect(
        ChatMessage.fromFirestore(data, hasPendingWrites: true).status,
        MessageStatus.sending,
      );
      expect(ChatMessage.fromFirestore(data).status, isNull);
    });
  });
}
