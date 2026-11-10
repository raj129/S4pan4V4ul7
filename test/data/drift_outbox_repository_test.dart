import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:photo_vault/features/chat/data/repositories/drift_outbox_repository.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/message_metadata.dart';
import 'package:photo_vault/features/chat/domain/repositories/outbox_repository.dart';
import 'package:photo_vault/core/storage/local_db/vault_database.dart';

void main() {
  late VaultDatabase db;
  late DriftOutboxRepository outbox;
  Directory? tempDirectory;
  sqlite.Database? lockDatabase;

  setUp(() {
    db = VaultDatabase.forTesting(NativeDatabase.memory());
    outbox = DriftOutboxRepository(db);
  });

  tearDown(() async {
    final lock = lockDatabase;
    lockDatabase = null;
    lock?.close();
    await db.close();
    final directory = tempDirectory;
    tempDirectory = null;
    if (directory != null) await directory.delete(recursive: true);
  });

  OutboxItem item(String messageId) => OutboxItem(
    messageId: messageId,
    threadId: 'a_b',
    senderId: 'a',
    encryptedText: 'cipher',
    recipientUid: 'b',
    preview: 'hi',
    queuedAt: DateTime.utc(2024, 1, 1),
  );

  test('attachment metadata survives a round trip through the queue', () async {
    await outbox.enqueue(
      OutboxItem(
        messageId: 'm1',
        threadId: 'a_b',
        senderId: 'a',
        encryptedText: 'cipher',
        recipientUid: 'b',
        preview: 'report.pdf',
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
    await outbox.enqueue(item('t1'));

    expect((await outbox.pending()).single.mediaMeta, isNull);
  });

  test(
    'concurrent failures increment attempts without losing updates',
    () async {
      await outbox.enqueue(item('m1'));

      await Future.wait([
        outbox.markFailed('m1', 'offline'),
        outbox.markFailed('m1', 'timeout'),
      ]);

      expect((await outbox.pending()).single.attempts, 2);
    },
  );

  test('a removed message is not recreated by a late failure update', () async {
    await outbox.enqueue(item('m1'));
    await outbox.remove('m1');

    await outbox.markFailed('m1', 'late failure');

    expect(await outbox.pending(), isEmpty);
  });

  test('failed-attempt writes retry after SQLITE_BUSY clears', () async {
    await db.close();
    tempDirectory = await Directory.systemTemp.createTemp('outbox-lock-test-');
    final path = '${tempDirectory!.path}${Platform.pathSeparator}outbox.sqlite';
    db = VaultDatabase.forTesting(
      NativeDatabase(
        File(path),
        setup: (database) => database.execute('PRAGMA busy_timeout = 0'),
      ),
    );
    outbox = DriftOutboxRepository(db);
    await outbox.enqueue(item('m1'));

    lockDatabase = sqlite.sqlite3.open(path);
    lockDatabase!.execute('BEGIN EXCLUSIVE TRANSACTION');
    final write = outbox.markFailed('m1', 'offline');
    await Future<void>.delayed(const Duration(milliseconds: 220));
    lockDatabase!.execute('COMMIT');
    await write;

    expect((await outbox.pending()).single.attempts, 1);
  });
}
