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

  static String _clearedBeforeKey(String threadId) =>
      'chat_cleared_before_$threadId';

  @override
  Future<void> setClearedBefore(String threadId, DateTime at) {
    return _db.upsertAppSetting(
      _clearedBeforeKey(threadId),
      at.toUtc().millisecondsSinceEpoch.toString(),
    );
  }

  @override
  Future<DateTime?> getClearedBefore(String threadId) async {
    return _parseMs(await _db.getAppSetting(_clearedBeforeKey(threadId)));
  }

  static const _clearedPrefix = 'chat_cleared_before_';
  static const _horizonKey = 'chat_history_horizon';

  @override
  Future<Map<String, DateTime>> getAllClearedBefore() async {
    final rows = await _db.getAppSettingsWithPrefix(_clearedPrefix);
    return {
      for (final row in rows)
        if (_parseMs(row.value) case final DateTime at)
          row.key.substring(_clearedPrefix.length): at,
    };
  }

  @override
  Future<DateTime?> getHistoryHorizon() async =>
      _parseMs(await _db.getAppSetting(_horizonKey));

  @override
  Future<void> setHistoryHorizon(DateTime? at) async {
    if (at == null) {
      await _db.deleteAppSetting(_horizonKey);
    } else {
      await _db.upsertAppSetting(
        _horizonKey,
        at.toUtc().millisecondsSinceEpoch.toString(),
      );
    }
  }

  @override
  Future<List<CachedMessageRecord>> exportAll() async {
    final rows = await _db.getEveryCachedMessage();
    return [
      for (final r in rows)
        CachedMessageRecord(
          messageId: r.messageId,
          threadId: r.threadId,
          senderId: r.senderId,
          encryptedText: r.encryptedText,
          sentAtMs: r.sentAtMs,
          payloadJson: r.payloadJson,
        ),
    ];
  }

  @override
  Future<void> importAll(List<CachedMessageRecord> records) {
    return _db.upsertCachedMessages([
      for (final r in records)
        CachedChatMessage(
          messageId: r.messageId,
          threadId: r.threadId,
          senderId: r.senderId,
          encryptedText: r.encryptedText,
          sentAtMs: r.sentAtMs,
          payloadJson: r.payloadJson,
        ),
    ]);
  }

  @override
  Future<String?> readSetting(String key) => _db.getAppSetting(key);

  @override
  Future<void> writeSetting(String key, String? value) async {
    if (value == null) {
      await _db.deleteAppSetting(key);
    } else {
      await _db.upsertAppSetting(key, value);
    }
  }

  static DateTime? _parseMs(String? raw) {
    if (raw == null) return null;
    final ms = int.tryParse(raw);
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  List<ChatMessage> _decodeAll(List<CachedChatMessage> rows) {
    final result = <ChatMessage>[];
    for (final row in rows) {
      final decoded = CachedMessageCodec.decode(row.payloadJson);
      if (decoded != null) result.add(decoded);
    }
    return result;
  }
}
