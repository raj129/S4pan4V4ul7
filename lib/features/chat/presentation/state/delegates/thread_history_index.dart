import '../../../domain/entities/chat_message.dart';
import '../../../domain/repositories/message_cache_repository.dart';

/// Read-only queries over one thread's cached history, used by the
/// scrollbar and jump-to-date.
///
/// Split out of `ActiveThreadCubit` (single responsibility): these are pure
/// lookups against [MessageCacheRepository] with no state of their own, so
/// they can be tested without spinning up the whole cubit.
class ThreadHistoryIndex {
  const ThreadHistoryIndex(this._cache);

  final MessageCacheRepository _cache;

  /// How many cached messages are older than [message], and the total.
  Future<({int older, int total})?> rankOf(
    String threadId,
    ChatMessage message,
  ) async {
    try {
      final total = await _cache.count(threadId);
      final older = await _cache.count(threadId, before: message.sentAt);
      return (older: older, total: total);
    } catch (_) {
      return null;
    }
  }

  /// The cached message at [fraction] (0 oldest .. 1 latest), with the total
  /// count so callers can tell whether it is within the newest page.
  Future<({ChatMessage? message, int offset, int total})?> atFraction(
    String threadId,
    double fraction,
  ) async {
    try {
      final total = await _cache.count(threadId);
      if (total == 0) return null;
      final offset = (fraction.clamp(0.0, 1.0) * (total - 1)).round();
      final message = await _cache.loadAtOffset(threadId, offset);
      return (message: message, offset: offset, total: total);
    } catch (_) {
      return null;
    }
  }

  /// Oldest and newest cached send times.
  Future<(DateTime, DateTime)?> bounds(String threadId) async {
    try {
      return await _cache.timeBounds(threadId);
    } catch (_) {
      return null;
    }
  }
}
