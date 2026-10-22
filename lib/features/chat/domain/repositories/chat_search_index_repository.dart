import '../entities/chat_message.dart';

/// One indexed message: its keyed search tokens (see `ChatSearchTokenizer`).
class ChatSearchEntry {
  const ChatSearchEntry({
    required this.messageId,
    required this.sentAt,
    required this.tokens,
  });

  final String messageId;
  final DateTime sentAt;

  /// Keyed hashes of the message's search terms — never the words.
  final List<String> tokens;
}

/// A message that matched a search.
class ChatSearchHit {
  const ChatSearchHit({required this.messageId, required this.sentAt});
  final String messageId;
  final DateTime sentAt;
}

/// Local keyed index over cached chat messages.
///
/// Holds only hashed tokens, so it is as unreadable without the in-memory
/// thread key as the ciphertext cache it indexes.
abstract class ChatSearchIndexRepository {
  /// Bumped whenever tokenization changes, so old entries are re-indexed.
  static const indexVersion = 1;

  /// Replace the index entries for [entries].
  Future<void> index(String threadId, List<ChatSearchEntry> entries);

  /// Drop the index entries of these messages.
  Future<void> remove(List<String> messageIds);

  /// Messages whose tokens include *every* one of [tokens], newest first.
  Future<List<ChatSearchHit>> search(String threadId, List<String> tokens);

  /// Cached messages (ciphertext) not yet indexed, newest first.
  Future<List<ChatMessage>> unindexed(String threadId, {int limit = 200});

  /// Number of cached messages not yet indexed.
  Future<int> countUnindexed(String threadId);
}

/// Index that stores nothing, for configurations without a local database.
class NoopChatSearchIndexRepository implements ChatSearchIndexRepository {
  const NoopChatSearchIndexRepository();

  @override
  Future<void> index(String threadId, List<ChatSearchEntry> entries) async {}

  @override
  Future<void> remove(List<String> messageIds) async {}

  @override
  Future<List<ChatSearchHit>> search(
    String threadId,
    List<String> tokens,
  ) async => const [];

  @override
  Future<List<ChatMessage>> unindexed(
    String threadId, {
    int limit = 200,
  }) async => const [];

  @override
  Future<int> countUnindexed(String threadId) async => 0;
}
