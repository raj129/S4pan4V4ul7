import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/data/repositories_impl/drift_outbox_repository.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/entities/message_metadata.dart';
import 'package:photo_vault/domain/repositories/outbox_repository.dart';
import 'package:photo_vault/storage/local_db/vault_database.dart';

void main() {
  late VaultDatabase db;
  late DriftOutboxRepository outbox;

  setUp(() {
    db = VaultDatabase.forTesting(NativeDatabase.memory());
    outbox = DriftOutboxRepository(db);
  });

  tearDown(() => db.close());

  test('attachment metadata survives a round trip through the queue', () async {
    await outbox.enqueue(
      OutboxItem(
        messageId: 'm1',
        threadId: 'a_b',
        senderId: 'a',
        encryptedText: 'cipher',
        recipientUid: 'b',
        preview: '📎 report.pdf',
        mediaType: MessageType.file,
        mediaRef: 'chat_media/a_b/m1/m1.bin.enc',
        mediaMeta: const MediaMeta(sizeBytes: 2048),
        queuedAt: DateTime.utc(2024, 1, 1),
      ),
    );

    final item = (await outbox.pendingForThread('a_b')).single;
    expect(item.mediaType, MessageType.file);
    expect(item.mediaMeta, const MediaMeta(sizeBytes: 2048));
    expect(item.toOptimisticMessage().mediaMeta?.readableSize, '2 KB');
  });

  test('text messages keep a null metadata column', () async {
    await outbox.enqueue(
      OutboxItem(
        messageId: 't1',
        threadId: 'a_b',
        senderId: 'a',
        encryptedText: 'cipher',
        recipientUid: 'b',
        preview: 'hi',
        queuedAt: DateTime.utc(2024, 1, 1),
      ),
    );

    expect((await outbox.pending()).single.mediaMeta, isNull);
  });
}
