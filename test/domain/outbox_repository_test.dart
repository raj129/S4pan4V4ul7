import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/entities/message_metadata.dart';
import 'package:photo_vault/domain/entities/message_reply.dart';
import 'package:photo_vault/domain/repositories/outbox_repository.dart';

OutboxItem _item({
  String messageId = 'm1',
  String? mediaRef,
  MessageType? mediaType,
  MessageReply? replyTo,
  int attempts = 0,
}) => OutboxItem(
  messageId: messageId,
  threadId: 'a_b',
  senderId: 'a',
  encryptedText: 'cipher',
  recipientUid: 'b',
  preview: '🔒 Message',
  mediaRef: mediaRef,
  mediaType: mediaType,
  replyTo: replyTo,
  queuedAt: DateTime.utc(2024, 1, 1, 12),
  attempts: attempts,
);

void main() {
  group('OutboxItem', () {
    test('a fresh entry renders as sending', () {
      final msg = _item().toOptimisticMessage();

      expect(msg.status, MessageStatus.sending);
      // The queued copy must carry the id it will be delivered under, otherwise
      // the optimistic bubble would never be replaced by the real one.
      expect(msg.messageId, 'm1');
      expect(msg.senderId, 'a');
      expect(msg.encryptedText, 'cipher');
      expect(msg.sentAt, DateTime.utc(2024, 1, 1, 12));
    });

    test('an entry that has already failed renders as failed', () {
      expect(
        _item(attempts: 1).toOptimisticMessage().status,
        MessageStatus.failed,
      );
    });

    test('carries media and reply metadata into the bubble', () {
      const reply = MessageReply(
        messageId: 'orig',
        senderId: 'b',
        encryptedPreview: 'quoted',
      );
      final msg = _item(
        mediaRef: 'threads/a_b/m1.jpg.enc',
        mediaType: MessageType.image,
        replyTo: reply,
      ).toOptimisticMessage();

      expect(msg.mediaRef, 'threads/a_b/m1.jpg.enc');
      expect(msg.mediaType, MessageType.image);
      expect(msg.replyTo, reply);
    });

    test('copyWith records the upload without disturbing identity', () {
      final updated = _item().copyWith(
        mediaRef: 'uploaded/path.enc',
        attempts: 2,
        lastError: 'network',
      );

      expect(updated.messageId, 'm1');
      expect(updated.queuedAt, DateTime.utc(2024, 1, 1, 12));
      expect(updated.mediaRef, 'uploaded/path.enc');
      expect(updated.attempts, 2);
      expect(updated.lastError, 'network');
    });
  });

  group('NoopOutboxRepository', () {
    test('accepts writes and stays empty', () async {
      // The in-memory test configuration has no database; sends must degrade to
      // online-only rather than throwing.
      const outbox = NoopOutboxRepository();

      await outbox.enqueue(_item());
      await outbox.markFailed('m1', 'boom');

      expect(await outbox.pending(), isEmpty);
      expect(await outbox.pendingForThread('a_b'), isEmpty);
      await outbox.remove('m1');
    });
  });
}
