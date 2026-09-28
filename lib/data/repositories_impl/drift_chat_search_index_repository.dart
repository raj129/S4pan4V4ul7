import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_search_index_repository.dart';
import '../../domain/repositories/message_cache_repository.dart';
import '../../storage/local_db/vault_database.dart';

/// Drift-backed keyed search index, stored next to the message cache.
class DriftChatSearchIndexRepository implements ChatSearchIndexRepository {
  DriftChatSearchIndexRepository(this._db);

  final VaultDatabase _db;

  @override
  Future<void> index(String threadId, List<ChatSearchEntry> entries) {
    return _db.indexChatMessages(threadId, [
      for (final e in entries)
        (
          messageId: e.messageId,
          sentAtMs: e.sentAt.toUtc().millisecondsSinceEpoch,
          tokens: e.tokens,
        ),
    ], version: ChatSearchIndexRepository.indexVersion);
  }

  @override
  Future<void> remove(List<String> messageIds) =>
      _db.removeFromSearchIndex(messageIds);

  @override
  Future<List<ChatSearchHit>> search(
    String threadId,
    List<String> tokens,
  ) async {
    final rows = await _db.searchChatIndex(threadId, tokens);
    return [
      for (final r in rows)
        ChatSearchHit(
          messageId: r.messageId,
          sentAt: DateTime.fromMillisecondsSinceEpoch(r.sentAtMs, isUtc: true),
        ),
    ];
  }

  @override
  Future<List<ChatMessage>> unindexed(
    String threadId, {
    int limit = 200,
  }) async {
    final rows = await _db.getUnindexedCachedMessages(
      threadId,
      version: ChatSearchIndexRepository.indexVersion,
      limit: limit,
    );
    final messages = <ChatMessage>[];
    final undecodable =
        <({String messageId, int sentAtMs, List<String> tokens})>[];
    for (final r in rows) {
      final m = CachedMessageCodec.decode(r.payloadJson);
      if (m != null) {
        messages.add(m);
      } else {
        // Nothing searchable; record it so the backfill never revisits it.
        undecodable.add((
          messageId: r.messageId,
          sentAtMs: r.sentAtMs,
          tokens: const [],
        ));
      }
    }
    if (undecodable.isNotEmpty) {
      await _db.indexChatMessages(
        threadId,
        undecodable,
        version: ChatSearchIndexRepository.indexVersion,
      );
    }
    return messages;
  }

  @override
  Future<int> countUnindexed(String threadId) =>
      _db.countUnindexedCachedMessages(
        threadId,
        version: ChatSearchIndexRepository.indexVersion,
      );
}
