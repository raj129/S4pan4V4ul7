import '../entities/chat_thread.dart';

abstract class ThreadRepository {
  /// Create a thread if it doesn't exist; return existing if it does.
  Future<ChatThread> createOrGetThread({
    required String myUid,
    required String otherUid,
  });

  /// Stream all threads for a user, ordered by lastMessageAt desc.
  Stream<List<ChatThread>> watchThreadsForUser(String uid);

  /// Fetch a single thread by ID.
  Future<ChatThread?> getThread(String threadId);

  /// Update the thread's last-message preview and timestamp.
  /// The preview is a placeholder string (e.g. "📷 Photo", "🎥 Video", or "🔒 Message")
  /// because actual content is encrypted.
  Future<void> updateLastMessage({
    required String threadId,
    required String preview,
    required DateTime sentAt,
  });

  /// Increment the unread count for a specific participant.
  Future<void> incrementUnread({
    required String threadId,
    required String recipientUid,
  });

  /// Reset the unread count to zero for the given user (mark thread as read).
  Future<void> resetUnread({
    required String threadId,
    required String uid,
  });

  /// Delete the entire thread and all its messages.
  Future<void> deleteThread(String threadId);

  /// Update the typing state for a user in a thread.
  Future<void> setTyping({
    required String threadId,
    required String uid,
    required bool isTyping,
  });

  /// Stream the typing state of the other user in a thread.
  Stream<bool> watchTyping({
    required String threadId,
    required String otherUid,
  });
}
