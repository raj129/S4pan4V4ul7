import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/message_metadata.dart';

ChatMessage _message({
  List<String> deliveredTo = const [],
  List<String> readBy = const [],
  Map<String, DateTime> deliveredAtBy = const {},
  Map<String, DateTime> readAtBy = const {},
}) => ChatMessage(
  messageId: 'message-1',
  threadId: 'sender_recipient',
  senderId: 'sender',
  encryptedText: 'ciphertext',
  sentAt: DateTime.utc(2026, 1, 1),
  deletedFor: const [],
  deliveredTo: deliveredTo,
  readBy: readBy,
  deliveredAtBy: deliveredAtBy,
  readAtBy: readAtBy,
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

    test('round-trips delivered and read timestamps by recipient', () {
      final deliveredAt = DateTime.utc(2026, 1, 1, 10, 5);
      final readAt = DateTime.utc(2026, 1, 1, 10, 7);
      final original = _message(
        deliveredTo: const ['recipient'],
        readBy: const ['recipient'],
        deliveredAtBy: {'recipient': deliveredAt},
        readAtBy: {'recipient': readAt},
      );

      final restored = ChatMessage.fromFirestore(original.toFirestore());

      expect(restored.deliveredAtBy['recipient'], deliveredAt);
      expect(restored.readAtBy['recipient'], readAt);
      expect(restored.copyWith(readAtBy: const {}).readAtBy, isEmpty);
    });

    test('older documents without receipt data remain compatible', () {
      final data = _message().toFirestore()
        ..remove('deliveredTo')
        ..remove('deliveredAtBy')
        ..remove('readAtBy');

      expect(ChatMessage.fromFirestore(data).deliveredTo, isEmpty);
      expect(ChatMessage.fromFirestore(data).deliveredAtBy, isEmpty);
      expect(ChatMessage.fromFirestore(data).readAtBy, isEmpty);
    });

    test('pending local Firestore writes remain in sending state', () {
      final data = _message().toFirestore();

      expect(
        ChatMessage.fromFirestore(data, hasPendingWrites: true).status,
        MessageStatus.sending,
      );
      expect(ChatMessage.fromFirestore(data).status, isNull);
    });

    test('ring-request events retain their type and delivery receipt', () {
      final original = ChatMessage(
        messageId: 'ring-1',
        threadId: 'sender_recipient',
        senderId: 'sender',
        encryptedText: 'ciphertext',
        sentAt: DateTime.utc(2026, 1, 1),
        deletedFor: const [],
        eventType: ChatEventType.ringRequest,
        deliveredTo: const ['recipient'],
      );

      final restored = ChatMessage.fromFirestore(original.toFirestore());

      expect(restored.eventType, ChatEventType.ringRequest);
      expect(restored.deliveredTo, ['recipient']);
      expect(
        restored.copyWith(deliveredTo: const []).eventType,
        ChatEventType.ringRequest,
      );
    });
  });
}
