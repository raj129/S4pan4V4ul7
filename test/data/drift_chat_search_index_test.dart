import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/chat_search_indexer.dart';
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/data/repositories_impl/drift_chat_search_index_repository.dart';
import 'package:photo_vault/data/repositories_impl/drift_message_cache_repository.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/storage/local_db/vault_database.dart';

class _KeyOnlyCrypto implements ChatCryptoService {
  @override
  Future<Uint8List> searchKey(String threadId) async =>
      Uint8List.fromList(List.filled(32, threadId.length));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

ChatMessage _msg(String id, int minute, {String thread = 't1'}) => ChatMessage(
  messageId: id,
  threadId: thread,
  senderId: 'other',
  encryptedText: 'cipher-$id',
  sentAt: DateTime.utc(2024, 1, 1).add(Duration(minutes: minute)),
  deletedFor: const [],
);

void main() {
  late VaultDatabase db;
  late DriftMessageCacheRepository cache;
  late DriftChatSearchIndexRepository index;
  late ChatSearchIndexer indexer;

  setUp(() {
    db = VaultDatabase.forTesting(NativeDatabase.memory());
    cache = DriftMessageCacheRepository(db);
    index = DriftChatSearchIndexRepository(db);
    indexer = ChatSearchIndexer(index: index, cryptoService: _KeyOnlyCrypto());
  });

  tearDown(() => db.close());

  test('finds messages by word prefix, newest first, per thread', () async {
    await cache.save([_msg('a', 1), _msg('b', 2), _msg('x', 3, thread: 't2')]);
    await indexer.indexTexts('t1', [
      (messageId: 'a', sentAt: _msg('a', 1).sentAt, text: 'lunch tomorrow'),
      (messageId: 'b', sentAt: _msg('b', 2).sentAt, text: 'Lunch at noon'),
    ]);
    await indexer.indexTexts('t2', [
      (messageId: 'x', sentAt: _msg('x', 3).sentAt, text: 'lunch elsewhere'),
    ]);

    final hits = await indexer.search('t1', 'lun');
    expect(hits.map((h) => h.messageId), ['b', 'a']);
    expect((await indexer.search('t1', 'lunch noon')).map((h) => h.messageId), [
      'b',
    ]);
    expect(await indexer.search('t1', 'dinner'), isEmpty);
  });

  test('re-indexing replaces old terms and removal drops them', () async {
    await cache.save([_msg('a', 1)]);
    final sentAt = _msg('a', 1).sentAt;
    await indexer.indexTexts('t1', [
      (messageId: 'a', sentAt: sentAt, text: 'old words'),
    ]);
    await indexer.indexTexts('t1', [
      (messageId: 'a', sentAt: sentAt, text: 'edited text'),
    ]);
    expect(await indexer.search('t1', 'old'), isEmpty);
    expect(await indexer.search('t1', 'edit'), hasLength(1));

    await cache.remove('a');
    expect(await indexer.search('t1', 'edit'), isEmpty);
  });

  test('tracks what still needs indexing', () async {
    await cache.save([for (var i = 0; i < 5; i++) _msg('m$i', i)]);
    expect(await index.countUnindexed('t1'), 5);

    final batch = await index.unindexed('t1', limit: 3);
    expect(batch, hasLength(3));
    await indexer.indexTexts('t1', [
      for (final m in batch)
        (messageId: m.messageId, sentAt: m.sentAt, text: null),
    ]);
    expect(await index.countUnindexed('t1'), 2);
  });

  test('clearing a thread clears its index', () async {
    await cache.save([_msg('a', 1)]);
    await indexer.indexTexts('t1', [
      (messageId: 'a', sentAt: _msg('a', 1).sentAt, text: 'hello'),
    ]);
    await cache.clearThread('t1');
    expect(await indexer.search('t1', 'hello'), isEmpty);
  });

  test('window queries page around a position in history', () async {
    await cache.save([for (var i = 0; i < 10; i++) _msg('m$i', i)]);

    expect(await cache.count('t1'), 10);
    expect(await cache.count('t1', before: _msg('m4', 4).sentAt), 4);
    expect((await cache.loadAtOffset('t1', 0))?.messageId, 'm0');
    expect((await cache.loadAtOffset('t1', 9))?.messageId, 'm9');
    expect(await cache.loadAtOffset('t1', 10), isNull);
    expect((await cache.loadById('m3'))?.messageId, 'm3');
    expect(
      (await cache.loadFrom(
        threadId: 't1',
        from: _msg('m7', 7).sentAt,
        limit: 5,
      )).map((m) => m.messageId),
      ['m7', 'm8', 'm9'],
    );
    final bounds = await cache.timeBounds('t1');
    expect(bounds?.$1, _msg('m0', 0).sentAt);
    expect(bounds?.$2, _msg('m9', 9).sentAt);
  });
}
