import '../entities/chat_message.dart';
import '../entities/message_metadata.dart';
import '../entities/message_reply.dart';

/// A message queued locally because it has not reached Firestore yet.
///
/// The text is already ciphertext — encryption happens before queueing, so a
/// queued message is no more readable on disk than a cached one.
class OutboxItem {
  const OutboxItem({
    required this.messageId,
    required this.threadId,
    required this.senderId,
    required this.encryptedText,
    required this.recipientUid,
    required this.preview,
    required this.queuedAt,
    this.mediaType,
    this.mediaRef,
    this.replyTo,
    this.attempts = 0,
    this.lastError,
  });

  final String messageId;
  final String threadId;
  final String senderId;
  final String encryptedText;

  /// Needed on delivery so the recipient's unread counter is still bumped.
  final String recipientUid;

  /// Thread-list preview: plaintext for text, a placeholder for media.
  final String preview;

  final MessageType? mediaType;

  /// Set once the media upload has succeeded, so a retry does not re-upload.
  final String? mediaRef;

  final MessageReply? replyTo;
  final DateTime queuedAt;
  final int attempts;
  final String? lastError;

  OutboxItem copyWith({String? mediaRef, int? attempts, String? lastError}) =>
      OutboxItem(
        messageId: messageId,
        threadId: threadId,
        senderId: senderId,
        encryptedText: encryptedText,
        recipientUid: recipientUid,
        preview: preview,
        queuedAt: queuedAt,
        mediaType: mediaType,
        mediaRef: mediaRef ?? this.mediaRef,
        replyTo: replyTo,
        attempts: attempts ?? this.attempts,
        lastError: lastError ?? this.lastError,
      );

  /// The optimistic bubble shown while the message is still queued.
  ChatMessage toOptimisticMessage() => ChatMessage(
    messageId: messageId,
    threadId: threadId,
    senderId: senderId,
    encryptedText: encryptedText,
    sentAt: queuedAt,
    deletedFor: const [],
    mediaRef: mediaRef,
    mediaType: mediaType,
    replyTo: replyTo,
    status: attempts > 0 ? MessageStatus.failed : MessageStatus.sending,
  );
}

/// Durable queue of outgoing messages.
///
/// Persisted rather than held in memory so a send survives the app being killed
/// while offline.
abstract class OutboxRepository {
  /// Add a message to the queue, or refresh one already there.
  Future<void> enqueue(OutboxItem item);

  /// Everything still waiting, oldest first.
  Future<List<OutboxItem>> pending();

  /// Everything still waiting in one thread, oldest first.
  Future<List<OutboxItem>> pendingForThread(String threadId);

  /// Remove a message once it has reached Firestore.
  Future<void> remove(String messageId);

  /// Record a failed attempt so the bubble can offer a retry.
  Future<void> markFailed(String messageId, String error);
}

/// Outbox that stores nothing.
///
/// Used when no local database is available (the in-memory test
/// configuration). Sends then behave as they did before: online-only.
class NoopOutboxRepository implements OutboxRepository {
  const NoopOutboxRepository();

  @override
  Future<void> enqueue(OutboxItem item) async {}

  @override
  Future<List<OutboxItem>> pending() async => const [];

  @override
  Future<List<OutboxItem>> pendingForThread(String threadId) async => const [];

  @override
  Future<void> remove(String messageId) async {}

  @override
  Future<void> markFailed(String messageId, String error) async {}
}
