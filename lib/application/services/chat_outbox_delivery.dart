import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_metadata.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/outbox_repository.dart';
import '../../domain/repositories/thread_repository.dart';
import 'chat_attachment_staging.dart';

class StagedAttachmentMissingException implements Exception {
  const StagedAttachmentMissingException(this.messageId);

  final String messageId;

  @override
  String toString() =>
      'The local attachment for message $messageId is no longer available.';
}

class OutboxDeliveryResult {
  const OutboxDeliveryResult({required this.item, required this.message});

  final OutboxItem item;
  final ChatMessage message;
}

/// Uploads staged ciphertext and then delivers the associated message.
///
/// This is shared by the foreground cubit and Android WorkManager so retries
/// use the same idempotent Storage paths and Firestore message ID.
class ChatOutboxDeliveryService {
  ChatOutboxDeliveryService({
    required this.outbox,
    required this.mediaRepository,
    required this.messageRepository,
    required this.threadRepository,
    required this.stagingStore,
  });

  final OutboxRepository outbox;
  final MediaRepository mediaRepository;
  final MessageRepository messageRepository;
  final ThreadRepository threadRepository;
  final AttachmentStagingStore stagingStore;

  static const _claimLease = Duration(minutes: 30);

  Future<OutboxDeliveryResult?> deliver({
    required OutboxItem item,
    required String uid,
    void Function(double progress)? onUploadProgress,
    UploadCancelToken? cancelToken,
  }) async {
    if (item.senderId != uid) {
      throw StateError('Cannot deliver another user\'s outbox item.');
    }
    if (!await outbox.tryClaim(
      item.messageId,
      DateTime.now().toUtc(),
      _claimLease,
    )) {
      return null;
    }

    try {
      var current = item;
      if (current.mediaType != null && current.mediaRef == null) {
        current = await _uploadMedia(
          current,
          onUploadProgress: onUploadProgress,
          cancelToken: cancelToken,
        );
      }
      if (current.mediaType != null && current.mediaRef == null) {
        throw StagedAttachmentMissingException(current.messageId);
      }

      final message = await messageRepository.sendMessage(
        threadId: current.threadId,
        senderId: current.senderId,
        encryptedText: current.encryptedText,
        messageId: current.messageId,
        sentAt: current.queuedAt,
        mediaRef: current.mediaRef,
        mediaType: current.mediaType,
        mediaMeta: current.mediaMeta,
        replyTo: current.replyTo,
      );
      await outbox.remove(current.messageId);
      await stagingStore.deleteMedia(current.messageId);
      await stagingStore.deleteThumbnail(current.messageId);
      await threadRepository.updateLastMessage(
        threadId: current.threadId,
        preview: current.preview,
        sentAt: message.sentAt,
      );
      await threadRepository.incrementUnread(
        threadId: current.threadId,
        recipientUid: current.recipientUid,
      );
      return OutboxDeliveryResult(item: current, message: message);
    } finally {
      await outbox.releaseClaim(item.messageId);
    }
  }

  Future<OutboxItem> _uploadMedia(
    OutboxItem item, {
    void Function(double progress)? onUploadProgress,
    UploadCancelToken? cancelToken,
  }) async {
    if (item.mediaType == null) return item;
    var current = item;

    if (current.mediaMeta?.thumbRef == null && current.hasStagedThumbnail) {
      final thumbnail = await stagingStore.readThumbnail(current.messageId);
      if (thumbnail == null) {
        throw StagedAttachmentMissingException(current.messageId);
      }
      final thumbPath = await mediaRepository.uploadEncryptedMedia(
        threadId: current.threadId,
        messageId: current.messageId,
        filename: '${current.messageId}.thumb.enc',
        encryptedBytes: thumbnail,
        cancelToken: cancelToken,
        onProgress: onUploadProgress == null
            ? null
            : (progress) => onUploadProgress(
                0.35 + (0.45 - 0.35) * progress.clamp(0.0, 1.0),
              ),
      );
      current = current.copyWith(
        mediaMeta:
            current.mediaMeta?.copyWith(thumbRef: thumbPath) ??
            MediaMeta(thumbRef: thumbPath),
        hasStagedThumbnail: false,
      );
      await outbox.enqueue(current);
      await stagingStore.deleteThumbnail(current.messageId);
    }

    if (!current.hasStagedMedia) {
      throw StagedAttachmentMissingException(current.messageId);
    }
    final encryptedBytes = await stagingStore.readMedia(current.messageId);
    if (encryptedBytes == null) {
      throw StagedAttachmentMissingException(current.messageId);
    }
    final mediaPath = await mediaRepository.uploadEncryptedMedia(
      threadId: current.threadId,
      messageId: current.messageId,
      filename: '${current.messageId}.${storageExtension(current.mediaType)}',
      encryptedBytes: encryptedBytes,
      cancelToken: cancelToken,
      onProgress: onUploadProgress == null
          ? null
          : (progress) =>
                onUploadProgress(0.45 + (1 - 0.45) * progress.clamp(0.0, 1.0)),
    );
    current = current.copyWith(mediaRef: mediaPath, hasStagedMedia: false);
    await outbox.enqueue(current);
    await stagingStore.deleteMedia(current.messageId);
    return current;
  }

  static String storageExtension(MessageType? type) => switch (type) {
    MessageType.video => 'mp4.enc',
    MessageType.file => 'bin.enc',
    _ => 'jpg.enc',
  };

  Future<void> discard(OutboxItem item) async {
    await outbox.remove(item.messageId);
    await stagingStore.deleteMedia(item.messageId);
    await stagingStore.deleteThumbnail(item.messageId);
    final mediaRef = item.mediaRef;
    final thumbRef = item.mediaMeta?.thumbRef;
    if (mediaRef != null) await mediaRepository.deleteMedia(mediaRef);
    if (thumbRef != null) await mediaRepository.deleteMedia(thumbRef);
  }
}
