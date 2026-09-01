import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/message_cache_repository.dart';
import '../../storage/local_db/vault_database.dart';

/// Drift-backed message cache, sharing the existing vault database.
class DriftMessageCacheRepository implements MessageCacheRepository {
  DriftMessageCacheRepository(this._db);

  final VaultDatabase _db;

  @override
  Future<List<ChatMessage>> load({
    required String threadId,
    int limit = 50,
    DateTime? before,
  }) async {
    final rows = await _db.getCachedMessages(
      threadId,
      limit: limit,
      beforeSentAtMs: before?.toUtc().millisecondsSinceEpoch,
    );
    return _decodeAll(rows);
  }

  @override
  Future<List<ChatMessage>> loadAll(String threadId) async {
    return _decodeAll(await _db.getAllCachedMessages(threadId));
  }

  @override
  Future<void> save(List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    await _db.upsertCachedMessages([
      for (final m in messages)
        CachedChatMessage(
          messageId: m.messageId,
          threadId: m.threadId,
          senderId: m.senderId,
          encryptedText: m.encryptedText,
          sentAtMs: m.sentAt.toUtc().millisecondsSinceEpoch,
          payloadJson: CachedMessageCodec.encode(m),
        ),
    ]);
  }

  @override
  Future<void> remove(String messageId) => _db.deleteCachedMessage(messageId);

  @override
  Future<void> clearThread(String threadId) => _db.deleteCachedThread(threadId);

  List<ChatMessage> _decodeAll(List<CachedChatMessage> rows) {
    final result = <ChatMessage>[];
    for (final row in rows) {
      final decoded = CachedMessageCodec.decode(row.payloadJson);
      if (decoded != null) result.add(decoded);
    }
    return result;
  }
}
