import 'dart:convert';

import '../entities/chat_message.dart';

/// Local, offline-first store of chat messages.
///
/// Holds ciphertext only — see the `ChatMessages` table doc for why. Callers
/// decrypt after reading, exactly as they do for Firestore results.
abstract class MessageCacheRepository {
  /// Newest-first page for a thread, optionally older than a cursor.
  Future<List<ChatMessage>> load({
    required String threadId,
    int limit = 50,
    DateTime? before,
  });

  /// Every cached message in a thread, newest first. Backs in-chat search.
  Future<List<ChatMessage>> loadAll(String threadId);

  /// Insert or refresh messages.
  Future<void> save(List<ChatMessage> messages);

  /// Remove a single message from the cache.
  Future<void> remove(String messageId);

  /// Remove an entire thread's cache.
  Future<void> clearThread(String threadId);

  /// Persist a local-only "cleared before" watermark for [threadId].
  ///
  /// Used to implement a WhatsApp/Signal-style "Clear chat": history at or
  /// before [at] is hidden on this device only. Nothing on the server (or
  /// the other participant's copy) is touched.
  Future<void> setClearedBefore(String threadId, DateTime at);

  /// The local "cleared before" watermark for [threadId], if any.
  Future<DateTime?> getClearedBefore(String threadId);

  /// Every thread's "cleared before" watermark, for chat backups.
  Future<Map<String, DateTime>> getAllClearedBefore();

  /// Device-wide history horizon: server messages sent at or before it are
  /// hidden unless they were restored into this cache from a backup. Set on a
  /// fresh install (or cleared data) so history only returns via restore.
  Future<DateTime?> getHistoryHorizon();

  Future<void> setHistoryHorizon(DateTime? at);

  /// Every cached row across all threads, verbatim, for chat backups.
  Future<List<CachedMessageRecord>> exportAll();

  /// Insert rows produced by [exportAll] (typically from a backup file).
  Future<void> importAll(List<CachedMessageRecord> records);

  /// Small per-device key/value flags used by the backup feature.
  Future<String?> readSetting(String key);

  Future<void> writeSetting(String key, String? value);
}

/// A raw cache row, ciphertext only. Used to move history in and out of
/// chat backups without decrypting it.
class CachedMessageRecord {
  const CachedMessageRecord({
    required this.messageId,
    required this.threadId,
    required this.senderId,
    required this.encryptedText,
    required this.sentAtMs,
    required this.payloadJson,
  });

  final String messageId;
  final String threadId;
  final String senderId;
  final String encryptedText;
  final int sentAtMs;
  final String payloadJson;

  Map<String, dynamic> toJson() => {
    'id': messageId,
    't': threadId,
    's': senderId,
    'e': encryptedText,
    'at': sentAtMs,
    'p': payloadJson,
  };

  static CachedMessageRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'], t = json['t'], s = json['s'];
    final e = json['e'], at = json['at'], p = json['p'];
    if (id is! String || t is! String || s is! String) return null;
    if (e is! String || at is! int || p is! String) return null;
    return CachedMessageRecord(
      messageId: id,
      threadId: t,
      senderId: s,
      encryptedText: e,
      sentAtMs: at,
      payloadJson: p,
    );
  }
}

/// Cache that stores nothing.
///
/// Used when no local database is available (the in-memory test
/// configuration). Chat degrades to online-only rather than failing.
class NoopMessageCacheRepository implements MessageCacheRepository {
  const NoopMessageCacheRepository();

  @override
  Future<List<ChatMessage>> load({
    required String threadId,
    int limit = 50,
    DateTime? before,
  }) async => const [];

  @override
  Future<List<ChatMessage>> loadAll(String threadId) async => const [];

  @override
  Future<void> save(List<ChatMessage> messages) async {}

  @override
  Future<void> remove(String messageId) async {}

  @override
  Future<void> clearThread(String threadId) async {}

  @override
  Future<void> setClearedBefore(String threadId, DateTime at) async {}

  @override
  Future<DateTime?> getClearedBefore(String threadId) async => null;

  @override
  Future<Map<String, DateTime>> getAllClearedBefore() async => const {};

  @override
  Future<DateTime?> getHistoryHorizon() async => null;

  @override
  Future<void> setHistoryHorizon(DateTime? at) async {}

  @override
  Future<List<CachedMessageRecord>> exportAll() async => const [];

  @override
  Future<void> importAll(List<CachedMessageRecord> records) async {}

  @override
  Future<String?> readSetting(String key) async => null;

  @override
  Future<void> writeSetting(String key, String? value) async {}
}

/// Serialisation shared by the cache implementation.
///
/// The whole Firestore map is stored verbatim so that fields added in later
/// versions survive a round trip through the cache without a schema change.
class CachedMessageCodec {
  const CachedMessageCodec._();

  static String encode(ChatMessage message) =>
      jsonEncode(message.toFirestore());

  static ChatMessage? decode(String payloadJson) {
    try {
      final map = jsonDecode(payloadJson);
      if (map is! Map) return null;
      return ChatMessage.fromFirestore(map.cast<String, dynamic>());
    } catch (_) {
      // A row written by a newer, incompatible version. Dropping it is safe:
      // the cache is a mirror of Firestore, never the source of truth.
      return null;
    }
  }
}
