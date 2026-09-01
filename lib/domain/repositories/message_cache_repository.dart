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
