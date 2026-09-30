import 'dart:typed_data';

import '../entities/chat_message.dart';
import '../entities/message_metadata.dart';
import '../entities/message_reply.dart';

abstract class MessageRepository {
  /// Send a message. Encryption must happen before calling this method.
  ///
  /// [messageId] may be supplied by the outbox so a queued send keeps a stable
  /// identity across retries; when omitted the repository generates one.
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String senderId,
    required String encryptedText,
    String? messageId,
    String? mediaRef,
    MessageType? mediaType,
    MediaMeta? mediaMeta,
    MessageReply? replyTo,
    bool isForwarded = false,
  });

  /// Stream messages for a thread, newest first.
  Stream<List<ChatMessage>> watchMessages(String threadId, {int limit = 30});

  /// Load older messages before a cursor timestamp (pagination).
  Future<List<ChatMessage>> loadBefore({
    required String threadId,
    required DateTime before,
    int limit = 30,
  });

  /// Load messages sent strictly after [after], oldest first.
  ///
  /// Used to catch the local cache up with everything that arrived while the
  /// thread was closed, so local search never has gaps.
  Future<List<ChatMessage>> loadAfter({
    required String threadId,
    required DateTime after,
    int limit = 100,
  });

  /// Fetch a single message, used to jump to the target of a reply.
  Future<ChatMessage?> getMessage({
    required String threadId,
    required String messageId,
  });

  /// Replace the ciphertext of an already-sent message and stamp `editedAt`.
  Future<void> editMessage({
    required String threadId,
    required String messageId,
    required String encryptedText,
  });

  /// Set or clear [uid]'s reaction on a message. A null [emoji] removes it.
  Future<void> setReaction({
    required String threadId,
    required String messageId,
    required String uid,
    required String? emoji,
  });

  /// Mark messages as read by [uid], driving the sender's read receipts.
  Future<void> markRead({
    required String threadId,
    required List<String> messageIds,
    required String uid,
  });

  /// Delete a message for the given user (appends uid to deletedFor).
  Future<void> deleteMessageForUser({
    required String threadId,
    required String messageId,
    required String uid,
  });

  /// Delete a message for everyone.
  ///
  /// Writes a tombstone rather than removing the document, so the recipient
  /// sees "This message was deleted" instead of the message silently vanishing.
  Future<void> deleteMessageForEveryone({
    required String threadId,
    required String messageId,
  });

  /// Delete all messages in a thread (used when deleting the thread).
  Future<void> deleteAllMessages(String threadId);
}

/// Lets the caller abort an in-flight upload.
class UploadCancelToken {
  bool _cancelled = false;
  void Function()? _onCancel;

  bool get isCancelled => _cancelled;

  /// Registered by the repository so cancelling reaches the running transfer.
  set onCancel(void Function()? callback) {
    _onCancel = callback;
    if (_cancelled) callback?.call();
  }

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _onCancel?.call();
  }
}

/// Thrown by an upload that was stopped through its [UploadCancelToken].
class UploadCancelledException implements Exception {
  const UploadCancelledException();

  @override
  String toString() => 'Upload cancelled';
}

abstract class MediaRepository {
  /// Upload an encrypted media blob to Firebase Storage.
  /// Returns the Storage path.
  ///
  /// [onProgress] receives a 0..1 fraction so the bubble can show a progress ring.
  /// Throws [UploadCancelledException] if [cancelToken] is cancelled.
  Future<String> uploadEncryptedMedia({
    required String threadId,
    required String messageId,
    required String filename,
    required Uint8List encryptedBytes,
    void Function(double progress)? onProgress,
    UploadCancelToken? cancelToken,
  });

  /// Download an encrypted media blob.
  Future<Uint8List> downloadEncryptedMedia(String storagePath);

  /// Delete encrypted media from Firebase Storage.
  Future<void> deleteMedia(String storagePath);

  /// Delete all media in a thread folder.
  Future<void> deleteThreadMedia(String threadId);
}
