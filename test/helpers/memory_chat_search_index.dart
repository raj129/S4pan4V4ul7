import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/repositories/chat_search_index_repository.dart';

import 'memory_message_cache.dart';

/// In-memory [ChatSearchIndexRepository] backed by a [MemoryMessageCache].
class MemoryChatSearchIndex implements ChatSearchIndexRepository {
  MemoryChatSearchIndex(this.cache);

  final MemoryMessageCache cache;

  /// messageId → entry.
  final Map<String, ({String threadId, ChatSearchEntry entry})> entries = {};

  @override
  Future<void> index(String threadId, List<ChatSearchEntry> list) async {
    for (final e in list) {
      entries[e.messageId] = (threadId: threadId, entry: e);
    }
  }

  @override
  Future<void> remove(List<String> messageIds) async {
    for (final id in messageIds) {
      entries.remove(id);
    }
  }

  @override
  Future<List<ChatSearchHit>> search(
    String threadId,
    List<String> tokens,
  ) async {
    final wanted = tokens.toSet();
    if (wanted.isEmpty) return const [];
    final hits =
        [
          for (final e in entries.values)
            if (e.threadId == threadId &&
                e.entry.tokens.toSet().containsAll(wanted))
              ChatSearchHit(
                messageId: e.entry.messageId,
                sentAt: e.entry.sentAt,
              ),
        ]..sort((a, b) {
          final t = b.sentAt.compareTo(a.sentAt);
          return t != 0 ? t : b.messageId.compareTo(a.messageId);
        });
    return hits;
  }

  @override
  Future<List<ChatMessage>> unindexed(
    String threadId, {
    int limit = 200,
  }) async {
    final all = await cache.loadAll(threadId);
    return all
        .where((m) => !entries.containsKey(m.messageId))
        .take(limit)
        .toList();
  }

  @override
  Future<int> countUnindexed(String threadId) async =>
      (await unindexed(threadId, limit: 1 << 30)).length;
}
