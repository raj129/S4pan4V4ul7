import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/repositories/message_cache_repository.dart';

/// In-memory [MessageCacheRepository] for tests.
class MemoryMessageCache implements MessageCacheRepository {
  final Map<String, CachedMessageRecord> rows = {};
  final Map<String, DateTime> cleared = {};
  final Map<String, String> settings = {};
  DateTime? horizon;

  List<ChatMessage> _decoded(String threadId, {DateTime? before}) {
    final list = [
      for (final r in rows.values)
        if (r.threadId == threadId &&
            (before == null || r.sentAtMs < before.millisecondsSinceEpoch))
          CachedMessageCodec.decode(r.payloadJson),
    ].whereType<ChatMessage>().toList()
      ..sort((a, b) => b.sentAt.compareTo(a.sentAt));
    return list;
  }

  @override
  Future<List<ChatMessage>> load({
    required String threadId,
    int limit = 50,
    DateTime? before,
  }) async => _decoded(threadId, before: before).take(limit).toList();

  @override
  Future<List<ChatMessage>> loadAll(String threadId) async =>
      _decoded(threadId);

  @override
  Future<void> save(List<ChatMessage> messages) async {
    for (final m in messages) {
      rows[m.messageId] = CachedMessageRecord(
        messageId: m.messageId,
        threadId: m.threadId,
        senderId: m.senderId,
        encryptedText: m.encryptedText,
        sentAtMs: m.sentAt.toUtc().millisecondsSinceEpoch,
        payloadJson: CachedMessageCodec.encode(m),
      );
    }
  }

  @override
  Future<void> remove(String messageId) async => rows.remove(messageId);

  @override
  Future<void> clearThread(String threadId) async =>
      rows.removeWhere((_, r) => r.threadId == threadId);

  @override
  Future<void> setClearedBefore(String threadId, DateTime at) async =>
      cleared[threadId] = at;

  @override
  Future<DateTime?> getClearedBefore(String threadId) async =>
      cleared[threadId];

  @override
  Future<Map<String, DateTime>> getAllClearedBefore() async => {...cleared};

  @override
  Future<DateTime?> getHistoryHorizon() async => horizon;

  @override
  Future<void> setHistoryHorizon(DateTime? at) async => horizon = at;

  @override
  Future<List<CachedMessageRecord>> exportAll() async => rows.values.toList();

  @override
  Future<void> importAll(List<CachedMessageRecord> records) async {
    for (final r in records) {
      rows[r.messageId] = r;
    }
  }

  @override
  Future<String?> readSetting(String key) async => settings[key];

  @override
  Future<void> writeSetting(String key, String? value) async {
    if (value == null) {
      settings.remove(key);
    } else {
      settings[key] = value;
    }
  }
}
