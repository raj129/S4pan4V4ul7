import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as img;

import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_local_media.dart';
import 'package:photo_vault/features/chat/application/media/android_chat_uploads.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_loader.dart';
import 'package:photo_vault/features/chat/application/media/chat_source_digest.dart';
import 'package:photo_vault/features/chat/application/media/image_compressor.dart';
import 'package:photo_vault/features/chat/application/media/video_compressor.dart';
import 'package:photo_vault/features/chat/application/media/media_send_status.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_user.dart';
import 'package:photo_vault/features/chat/domain/entities/message_metadata.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/outbox_repository.dart';

class OutgoingImageItem {
  const OutgoingImageItem({
    required this.messageId,
    required this.bytes,
    this.sourceUri,
    this.sourceFlags = 0,
    this.filename,
  });

  final String messageId;
  final Uint8List bytes;
  final String? sourceUri;
  final int sourceFlags;
  final String? filename;
}

class OutgoingVideoItem {
  const OutgoingVideoItem({
    required this.messageId,
    required this.bytes,
    this.sourceUri,
    this.sourceFlags = 0,
    this.filename,
  });

  final String messageId;
  final Uint8List bytes;
  final String? sourceUri;
  final int sourceFlags;
  final String? filename;
}

/// Coordinates media sending, compression, native Android background uploads,
/// cross-platform Firebase Storage uploads, progress tracking, and cancellations.
class ThreadUploadCoordinator {
  ThreadUploadCoordinator({
    required AndroidChatUploads? androidUploads,
    required AndroidChatLocalMedia? localMedia,
    required ChatMediaLoader? mediaLoader,
    required MediaRepository mediaRepository,
    required ChatCryptoService cryptoService,
    required OutboxRepository outbox,
    required MessageCacheRepository messageCache,
    required ImageCompressor imageCompressor,
    VideoCompressor videoCompressor = const VideoCompressor(),
    required void Function(String storagePath, Uint8List bytes)? onMediaReady,
    required String myUid,
    required String? Function() currentThreadId,
    required ChatUser? Function() otherUser,
    required bool Function() isClosed,
    required bool Function(String messageId) isBufferContaining,
    required ChatMessage? Function(String messageId) getBufferMessage,
    required ChatMessage? Function(String messageId) getPendingMessage,
    required void Function(String messageId, ChatMessage message)
    setPendingMessage,
    required ChatMessage? Function(String messageId) removePendingMessage,
    required List<ChatMessage> Function(List<ChatMessage> msgs)
    afterClearWatermark,
    required void Function(String messageId, MediaSendStatus? status)
    setUploadStatus,
    required void Function(
      String messageId,
      MediaSendPhase phase,
      double progress,
    )
    advanceUpload,
    required void Function() emitMessages,
    required void Function(String message) reportActionError,
    required Future<void> Function(String messageId) discardMessage,
    required Future<void> Function(OutboxItem item, {String? decryptedPreview})
    deliverOutboxItem,
    required Future<List<ChatMessage>> Function(
      List<ChatMessage> msgs,
      String threadId,
    )
    decryptAll,
    required void Function(
      OutboxItem item,
      String? decryptedPreview, {
      MessageStatus? status,
    })
    showPending,
  }) : _androidUploads = androidUploads,
       _localMedia = localMedia,
       _mediaLoader = mediaLoader,
       _mediaRepository = mediaRepository,
       _cryptoService = cryptoService,
       _outbox = outbox,
       _messageCache = messageCache,
       _imageCompressor = imageCompressor,
       _videoCompressor = videoCompressor,
       _onMediaReady = onMediaReady,
       _myUid = myUid,
       _currentThreadId = currentThreadId,
       _otherUser = otherUser,
       _isClosed = isClosed,
       _isBufferContaining = isBufferContaining,
       _getBufferMessage = getBufferMessage,
       _getPendingMessage = getPendingMessage,
       _setPendingMessage = setPendingMessage,
       _removePendingMessage = removePendingMessage,
       _afterClearWatermark = afterClearWatermark,
       _setUploadStatus = setUploadStatus,
       _advanceUpload = advanceUpload,
       _emitMessages = emitMessages,
       _reportActionError = reportActionError,
       _discardMessage = discardMessage,
       _deliverOutboxItem = deliverOutboxItem,
       _decryptAll = decryptAll,
       _showPending = showPending;

  final AndroidChatUploads? _androidUploads;
  final AndroidChatLocalMedia? _localMedia;
  final ChatMediaLoader? _mediaLoader;
  final MediaRepository _mediaRepository;
  final ChatCryptoService _cryptoService;
  final OutboxRepository _outbox;
  final MessageCacheRepository _messageCache;
  final ImageCompressor _imageCompressor;
  final VideoCompressor _videoCompressor;
  final void Function(String storagePath, Uint8List bytes)? _onMediaReady;
  final String _myUid;

  final String? Function() _currentThreadId;
  final ChatUser? Function() _otherUser;
  final bool Function() _isClosed;
  final bool Function(String messageId) _isBufferContaining;
  final ChatMessage? Function(String messageId) _getBufferMessage;
  final ChatMessage? Function(String messageId) _getPendingMessage;
  final void Function(String messageId, ChatMessage message) _setPendingMessage;
  final ChatMessage? Function(String messageId) _removePendingMessage;
  final List<ChatMessage> Function(List<ChatMessage> msgs) _afterClearWatermark;
  final void Function(String messageId, MediaSendStatus? status)
  _setUploadStatus;
  final void Function(String messageId, MediaSendPhase phase, double progress)
  _advanceUpload;
  final void Function() _emitMessages;
  final void Function(String message) _reportActionError;
  final Future<void> Function(String messageId) _discardMessage;
  final Future<void> Function(OutboxItem item, {String? decryptedPreview})
  _deliverOutboxItem;
  final Future<List<ChatMessage>> Function(
    List<ChatMessage> msgs,
    String threadId,
  )
  _decryptAll;
  final void Function(
    OutboxItem item,
    String? decryptedPreview, {
    MessageStatus? status,
  })
  _showPending;

  StreamSubscription<List<AndroidUploadJob>>? _androidUploadSub;
  final Set<String> _acknowledgedUploads = {};
  final Map<String, UploadCancelToken> _uploadTokens = {};
  final Set<String> _queuedBatchIds = {};

  static const maxAttachmentBytes = 64 * 1024 * 1024 - 1024;

  static String storageExtension(MessageType? type) => switch (type) {
    MessageType.video => 'mp4.enc',
    MessageType.gif => 'gif.enc',
    MessageType.sticker => 'sticker.enc',
    MessageType.file => 'bin.enc',
    _ => 'jpg.enc',
  };

  static MediaMeta buildMediaMeta(
    MessageType type,
    Uint8List bytes, {
    int? width,
    int? height,
  }) {
    if (type == MessageType.image && (width == null || height == null)) {
      try {
        final info = img.findDecoderForData(bytes)?.startDecode(bytes);
        width = info?.width;
        height = info?.height;
      } catch (_) {}
    }
    return MediaMeta(width: width, height: height, sizeBytes: bytes.length);
  }

  void initialize() {
    _androidUploadSub = _androidUploads?.changes.listen(
      syncAndroidUploads,
      onError: (Object error) =>
          _reportActionError('Could not read upload status.'),
    );
  }

  bool isUploading(String messageId) {
    if (_uploadTokens.containsKey(messageId)) return true;
    final jobs = _androidUploads?.jobs;
    if (jobs != null) {
      for (final job in jobs) {
        if (job.message.messageId == messageId &&
            job.status.lifecycle != MediaUploadLifecycle.completed) {
          return true;
        }
      }
    }
    return false;
  }

  bool isAndroidJob(String messageId) =>
      _androidUploads?.jobs.any((job) => job.message.messageId == messageId) ??
      false;

  Future<void> retryAndroidJob(String messageId) async {
    await _androidUploads?.retry(messageId);
  }

  Future<bool> tryRecoverAndroidOutboxItem(OutboxItem item) async {
    final uploads = _androidUploads;
    if (uploads != null && item.mediaType != null) {
      if (item.mediaRef == null) {
        _reportActionError(
          'This older attachment cannot be recovered. Reattach the original file.',
        );
        return true;
      }
      await uploads.recoverUploaded(
        item.toOptimisticMessage(),
        item.recipientUid,
      );
      await _outbox.remove(item.messageId);
      await syncAndroidUploads(uploads.jobs);
      return true;
    }
    return false;
  }

  Future<void> syncAndroidUploads(List<AndroidUploadJob> jobs) async {
    if (_isClosed()) return;
    final threadId = _currentThreadId();
    for (final job in jobs) {
      var message = job.message;
      if (message.senderId != _myUid ||
          message.threadId != threadId ||
          _afterClearWatermark([message]).isEmpty) {
        continue;
      }
      if (job.status.lifecycle == MediaUploadLifecycle.cancelled) {
        _removePendingMessage(message.messageId);
        _setUploadStatus(message.messageId, null);
        continue;
      }
      if (_isBufferContaining(message.messageId)) {
        _removePendingMessage(message.messageId);
        _setUploadStatus(message.messageId, null);
        if (job.status.lifecycle == MediaUploadLifecycle.completed &&
            _acknowledgedUploads.add(message.messageId)) {
          try {
            // Retire the native intent only after the canonical server copy
            // (including edits, receipts and tombstones) is durable locally.
            final bufferMsg = _getBufferMessage(message.messageId);
            if (bufferMsg != null) {
              await _messageCache.save([bufferMsg]);
            }
            await _androidUploads!.acknowledge(message.messageId);
          } catch (_) {
            _acknowledgedUploads.remove(message.messageId);
            _reportActionError(
              'Upload sent; local recovery checkpoint could not be saved.',
            );
          }
          if (_isClosed() || _currentThreadId() != threadId) return;
        }
        continue;
      }
      final existing = _getPendingMessage(message.messageId);
      if (existing?.localDecryptedText == null) {
        message = (await _decryptAll([message], message.threadId)).single;
        if (_isClosed() || _currentThreadId() != threadId) return;
      } else {
        message = message.withDecryptedText(existing!.localDecryptedText!);
      }
      _setPendingMessage(message.messageId, message);
      _setUploadStatus(
        message.messageId,
        job.status.lifecycle == MediaUploadLifecycle.completed
            ? null
            : job.status,
      );
    }
    _emitMessages();
  }

  Future<void> pauseUpload(String messageId) async {
    try {
      await _androidUploads?.pause(messageId);
    } catch (_) {
      _reportActionError('Could not pause the upload. Retry from the chat.');
    }
  }

  Future<void> resumeUpload(String messageId) async {
    try {
      await _androidUploads?.resume(messageId);
    } catch (_) {
      _reportActionError('Could not resume the upload. Retry from the chat.');
    }
  }

  /// Abort a send that is still being prepared or uploaded, and remove its
  /// bubble. Has no effect once delivery has started.
  Future<void> cancelUpload(String messageId) async {
    final token = _uploadTokens[messageId];
    if (token != null) token.cancel();
    if (_queuedBatchIds.remove(messageId)) {
      _setUploadStatus(messageId, null);
      await _discardMessage(messageId);
      return;
    }
    final job = _androidUploads?.jobs
        .where((job) => job.message.messageId == messageId)
        .firstOrNull;
    if (job != null) {
      await _androidUploads!.cancel(messageId);
      await removeLocalAttachment(job.message);
      await syncAndroidUploads(_androidUploads.jobs);
      return;
    }
    if (token == null) return;
    _setUploadStatus(messageId, null);
    await _discardMessage(messageId);
  }

  Future<void> _deleteQuietly(String? storagePath) async {
    if (storagePath == null) return;
    try {
      await _mediaRepository.deleteMedia(storagePath);
    } catch (_) {}
  }

  Future<void> removeLocalAttachment(ChatMessage message) async {
    final local = _localMedia;
    if (local == null) return;
    final loader = _mediaLoader;
    if (loader != null && loader.accountId != _myUid) {
      throw StateError('Chat account changed before attachment cleanup.');
    }
    for (final path in {
      if (message.mediaRef != null) message.mediaRef!,
      if (message.mediaMeta?.thumbRef != null) message.mediaMeta!.thumbRef!,
    }) {
      if (loader != null) {
        await loader.removeLocal(path);
      } else {
        await local.remove(_myUid, path);
      }
    }
  }

  Future<void> _sendAndroidMedia({
    required String messageId,
    required List<int> rawBytes,
    required MessageType type,
    String? filename,
    required ImageQuality quality,
    VideoQuality videoQuality = VideoQuality.high,
    bool propagateFailure = false,
    String? sourceUri,
    int sourceFlags = 0,
  }) async {
    final uploads = _androidUploads!;
    final threadId = _currentThreadId();
    final recipient = _otherUser()?.uid;
    if (threadId == null || recipient == null) {
      if (propagateFailure) throw StateError('Open a chat before recording.');
      return;
    }
    if (_uploadTokens.containsKey(messageId) ||
        uploads.jobs.any((job) => job.message.messageId == messageId)) {
      _reportActionError('This attachment is already queued.');
      if (propagateFailure) {
        throw StateError('This attachment is already queued.');
      }
      return;
    }
    if (rawBytes.isEmpty || rawBytes.length > maxAttachmentBytes) {
      _reportActionError(
        'Attachments must be nonempty and smaller than 64 MB.',
      );
      if (propagateFailure) {
        throw StateError('Attachment is empty or too large.');
      }
      return;
    }
    final token = _uploadTokens[messageId] = UploadCancelToken();
    final bytes = Uint8List.fromList(rawBytes);
    Uint8List? preparedBytes;
    Uint8List? thumb;
    final retained = <String>[];
    var handoffStarted = false;
    try {
      _setUploadStatus(messageId, const MediaSendStatus.preparing());
      final preview = ChatMessage.mediaPreviewFor(type, filename: filename);
      final text = await _cryptoService.encryptMessage(
        threadId: threadId,
        plaintext: preview,
      );
      if (token.isCancelled) throw const UploadCancelledException();
      var meta = buildMediaMeta(type, bytes);
      final mediaRef = 'chat_media/$threadId/$messageId/media.enc';
      var outboxItem = OutboxItem(
        messageId: messageId,
        threadId: threadId,
        senderId: _myUid,
        encryptedText: text,
        recipientUid: recipient,
        preview: preview,
        mediaType: type,
        mediaRef: mediaRef,
        mediaMeta: meta,
        queuedAt: DateTime.now().toUtc(),
      );
      await _outbox.enqueue(outboxItem);
      _setPendingMessage(
        messageId,
        ChatMessage(
          messageId: messageId,
          threadId: threadId,
          senderId: _myUid,
          encryptedText: text,
          sentAt: DateTime.now().toUtc(),
          deletedFor: const [],
          mediaType: type,
          mediaRef: mediaRef,
          mediaMeta: meta,
          localDecryptedText: preview,
          status: MessageStatus.sending,
        ),
      );
      _emitMessages();
      if (type == MessageType.image) {
        final prepared = await _imageCompressor.prepare(
          bytes: bytes,
          quality: quality,
        );
        preparedBytes = Uint8List.fromList(prepared.bytes);
        thumb = prepared.thumbnail.isEmpty
            ? null
            : Uint8List.fromList(prepared.thumbnail);
        meta = buildMediaMeta(
          type,
          preparedBytes,
          width: prepared.width,
          height: prepared.height,
        );
      } else if (type == MessageType.video) {
        final prepared = await _videoCompressor.prepare(
          bytes: bytes,
          quality: videoQuality,
        );
        preparedBytes = Uint8List.fromList(prepared.bytes);
        thumb = prepared.thumbnail.isEmpty
            ? null
            : Uint8List.fromList(prepared.thumbnail);
        meta = MediaMeta(
          width: prepared.width > 0 ? prepared.width : null,
          height: prepared.height > 0 ? prepared.height : null,
          sizeBytes: preparedBytes.length,
          durationMs: prepared.durationMs > 0 ? prepared.durationMs : null,
        );
      } else {
        preparedBytes = bytes;
      }
      if (token.isCancelled) throw const UploadCancelledException();
      if (preparedBytes.length > maxAttachmentBytes) {
        throw StateError('Attachments must be smaller than 64 MB.');
      }
      if (thumb != null) {
        final ref = 'chat_media/$threadId/$messageId/thumb.enc';
        meta = meta.copyWith(thumbRef: ref);
        outboxItem = outboxItem.copyWith(mediaMeta: meta);
        await _outbox.enqueue(outboxItem);
        _onMediaReady?.call(ref, thumb);
      } else if (type == MessageType.image || type == MessageType.video) {
        _onMediaReady?.call(mediaRef, preparedBytes);
      }
      final message = ChatMessage(
        messageId: messageId,
        threadId: threadId,
        senderId: _myUid,
        encryptedText: text,
        sentAt: DateTime.now().toUtc(),
        deletedFor: const [],
        mediaType: type,
        mediaRef: mediaRef,
        mediaMeta: meta,
        localDecryptedText: preview,
        status: MessageStatus.sending,
      );
      _setPendingMessage(messageId, message);
      _emitMessages();
      _setUploadStatus(
        messageId,
        const MediaSendStatus(phase: MediaSendPhase.encrypting, progress: 0),
      );
      final ciphertext = await _cryptoService.encryptMedia(
        threadId: threadId,
        bytes: preparedBytes,
      );
      final encryptedThumb = thumb == null
          ? null
          : await _cryptoService.encryptMedia(threadId: threadId, bytes: thumb);
      if (token.isCancelled) throw const UploadCancelledException();
      if (_localMedia != null) {
        await _localMedia.put(
          uid: _myUid,
          path: mediaRef,
          direction: ChatMediaDirection.sent,
          ciphertext: ciphertext,
          sourceUri: sourceUri,
          sourceDigest: sourceUri == null
              ? null
              : await chatSourceDigest(bytes),
          sourceFlags: sourceFlags,
        );
        retained.add(mediaRef);
        if (encryptedThumb != null) {
          await _localMedia.put(
            uid: _myUid,
            path: meta.thumbRef!,
            direction: ChatMediaDirection.sent,
            ciphertext: encryptedThumb,
          );
          retained.add(meta.thumbRef!);
        }
        if (token.isCancelled) throw const UploadCancelledException();
      }
      handoffStarted = true;
      await uploads.enqueue(
        message: message,
        recipientUid: recipient,
        ciphertext: ciphertext,
        thumbnail: encryptedThumb,
      );
      await _outbox.remove(messageId);
      // Deletion during the channel commit must cancel the newly accepted
      // native intent rather than leave an unseen upload running.
      if (token.isCancelled) {
        await uploads.cancel(messageId);
        throw const UploadCancelledException();
      }
      await syncAndroidUploads(uploads.jobs);
    } on UploadCancelledException {
      await _outbox.remove(messageId);
      var cleanupIncomplete = false;
      if (_localMedia != null) {
        for (final variant in ['media.enc', 'thumb.enc']) {
          try {
            await _localMedia.remove(
              _myUid,
              'chat_media/$threadId/$messageId/$variant',
            );
          } on ChatLocalMediaException catch (cleanupError) {
            cleanupIncomplete = true;
            debugPrint(
              'Chat cancelled staging cleanup failure=${cleanupError.code}',
            );
          }
        }
      }
      _removePendingMessage(messageId);
      _setUploadStatus(messageId, null);
      _emitMessages();
      if (cleanupIncomplete && !_isClosed()) {
        _reportActionError(
          'Upload cancelled. Encrypted staging cleanup is incomplete; check sign-in and free storage before removing the local attachment.',
        );
      }
      if (propagateFailure) rethrow;
    } catch (error) {
      await _outbox.remove(messageId);
      var cleanupIncomplete = false;
      if (!handoffStarted && _localMedia != null) {
        for (final path in retained) {
          try {
            await _localMedia.remove(_myUid, path);
          } on ChatLocalMediaException catch (cleanupError) {
            cleanupIncomplete = true;
            debugPrint('Chat sent rollback failure=${cleanupError.code}');
          }
        }
      }
      _removePendingMessage(messageId);
      _setUploadStatus(messageId, null);
      _emitMessages();
      _reportActionError(
        'Could not queue encrypted attachment: $error'
        '${cleanupIncomplete ? ' Encrypted staging cleanup is incomplete; free storage and retry cleanup.' : ''}',
      );
      if (propagateFailure) rethrow;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      preparedBytes?.fillRange(0, preparedBytes.length, 0);
      thumb?.fillRange(0, thumb.length, 0);
      _uploadTokens.remove(messageId);
    }
  }

  /// Encrypt, upload and send an attachment.
  Future<void> sendMedia({
    required String messageId,
    required List<int> rawBytes,
    required MessageType type,
    String? filename,
    ImageQuality quality = ImageQuality.high,
    VideoQuality videoQuality = VideoQuality.high,
    bool propagateFailure = false,
    String? sourceUri,
    int sourceFlags = 0,
  }) async {
    final threadId = _currentThreadId();
    if (threadId == null) {
      if (propagateFailure) throw StateError('Chat is no longer open.');
      return;
    }
    if (_androidUploads != null) {
      await _sendAndroidMedia(
        messageId: messageId,
        rawBytes: rawBytes,
        type: type,
        filename: filename,
        quality: quality,
        videoQuality: videoQuality,
        propagateFailure: propagateFailure,
        sourceUri: sourceUri,
        sourceFlags: sourceFlags,
      );
      return;
    }
    if (rawBytes.isEmpty) {
      _reportActionError('That file is empty.');
      return;
    }
    final other = _otherUser();
    if (other == null) {
      if (propagateFailure) throw StateError('Recipient unavailable.');
      return;
    }
    final preview = ChatMessage.mediaPreviewFor(type, filename: filename);
    final token = _uploadTokens[messageId] = UploadCancelToken();
    void throwIfCancelled() {
      if (token.isCancelled) throw const UploadCancelledException();
    }

    String? thumbPath;
    String? storagePath;
    try {
      var bytes = rawBytes is Uint8List
          ? rawBytes
          : Uint8List.fromList(rawBytes);

      final encryptedText = await _cryptoService.encryptMessage(
        threadId: threadId,
        plaintext: preview,
      );
      // Queued with no mediaRef yet: an entry without one is not deliverable
      // and drainOutbox deliberately refuses to send it.
      var item = OutboxItem(
        messageId: messageId,
        threadId: threadId,
        senderId: _myUid,
        encryptedText: encryptedText,
        recipientUid: other.uid,
        preview: preview,
        mediaType: type,
        mediaMeta: buildMediaMeta(type, bytes),
        queuedAt: DateTime.now().toUtc(),
      );
      await _outbox.enqueue(item);
      throwIfCancelled();
      _showPending(item, preview);
      _setUploadStatus(messageId, const MediaSendStatus.preparing());

      try {
        Uint8List? thumbnail;
        if (type == MessageType.image) {
          final prepared = await _imageCompressor.prepare(
            bytes: bytes,
            quality: quality,
          );
          bytes = prepared.bytes;
          thumbnail = prepared.thumbnail.isEmpty ? null : prepared.thumbnail;
          // Re-published so the bubble reserves the final aspect ratio using
          // the compressed dimensions rather than the originals.
          item = item.copyWith(
            mediaMeta: buildMediaMeta(
              type,
              bytes,
              width: prepared.width == 0 ? null : prepared.width,
              height: prepared.height == 0 ? null : prepared.height,
            ),
          );
          throwIfCancelled();
          _showPending(item, preview);
        } else if (type == MessageType.video) {
          final prepared = await _videoCompressor.prepare(
            bytes: bytes,
            quality: videoQuality,
          );
          bytes = prepared.bytes;
          thumbnail = prepared.thumbnail.isEmpty ? null : prepared.thumbnail;
          item = item.copyWith(
            mediaMeta: MediaMeta(
              width: prepared.width > 0 ? prepared.width : null,
              height: prepared.height > 0 ? prepared.height : null,
              sizeBytes: bytes.length,
              durationMs: prepared.durationMs > 0 ? prepared.durationMs : null,
            ),
          );
          throwIfCancelled();
          _showPending(item, preview);
        }
        throwIfCancelled();
        _advanceUpload(
          messageId,
          MediaSendPhase.encrypting,
          MediaSendWeights.compressEnd,
        );

        // Checked after compression, so a large photo can still go through at
        // a lower quality. The bubble already exists, so it has to be taken
        // back rather than simply not created.
        if (bytes.length > maxAttachmentBytes) {
          await _discardMessage(messageId);
          _reportActionError('Attachments must be smaller than 64 MB.');
          return;
        }

        if (thumbnail != null) {
          final encryptedThumb = await _cryptoService.encryptMedia(
            threadId: threadId,
            bytes: thumbnail,
          );
          thumbPath = await _mediaRepository.uploadEncryptedMedia(
            threadId: threadId,
            messageId: messageId,
            filename: '$messageId.thumb.enc',
            encryptedBytes: encryptedThumb,
            cancelToken: token,
            onProgress: (p) => _advanceUpload(
              messageId,
              MediaSendPhase.uploading,
              MediaSendWeights.span(
                MediaSendWeights.compressEnd,
                MediaSendWeights.thumbEnd,
                p,
              ),
            ),
          );
          // The device already has these bytes; publishing them means the
          // sender's own bubble never downloads its own thumbnail.
          _onMediaReady?.call(thumbPath, thumbnail);
        }
        _advanceUpload(
          messageId,
          MediaSendPhase.encrypting,
          MediaSendWeights.thumbEnd,
        );

        throwIfCancelled();
        final encrypted = await _cryptoService.encryptMedia(
          threadId: threadId,
          bytes: bytes,
        );
        throwIfCancelled();
        storagePath = await _mediaRepository.uploadEncryptedMedia(
          threadId: threadId,
          messageId: messageId,
          filename: '$messageId.${storageExtension(type)}',
          encryptedBytes: encrypted,
          cancelToken: token,
          onProgress: (p) => _advanceUpload(
            messageId,
            MediaSendPhase.uploading,
            MediaSendWeights.span(MediaSendWeights.thumbEnd, 1, p),
          ),
        );
        throwIfCancelled();
        if (type == MessageType.image) {
          _onMediaReady?.call(storagePath, bytes);
        }

        // Recorded so a retry reuses the upload instead of repeating it.
        item = item.copyWith(
          mediaRef: storagePath,
          mediaMeta: thumbPath == null
              ? item.mediaMeta
              : item.mediaMeta?.copyWith(thumbRef: thumbPath) ??
                    MediaMeta(thumbRef: thumbPath),
        );
        await _outbox.enqueue(item);
      } finally {
        _setUploadStatus(messageId, null);
      }
      // Past this point the message is being written; cancelling is over.
      _uploadTokens.remove(messageId);
      await _deliverOutboxItem(item, decryptedPreview: preview);
    } on UploadCancelledException {
      _setUploadStatus(messageId, null);
      await _discardMessage(messageId);
      await _deleteQuietly(thumbPath);
      await _deleteQuietly(storagePath);
    } catch (e) {
      _setUploadStatus(messageId, null);
      await _outbox.markFailed(messageId, e.toString());
      _reportActionError('Media send failed: $e');
    } finally {
      _uploadTokens.remove(messageId);
    }
  }

  /// Queue multiple images at once, publishing optimistic bubbles immediately
  /// while processing preparations sequentially in the background.
  Future<void> sendMultipleImages({
    required List<OutgoingImageItem> items,
    required ImageQuality quality,
  }) async {
    if (items.isEmpty) return;
    final threadId = _currentThreadId();
    if (threadId == null) return;

    for (final item in items) {
      final preview = ChatMessage.mediaPreviewFor(
        MessageType.image,
        filename: item.filename,
      );
      final meta = buildMediaMeta(MessageType.image, item.bytes);
      _setPendingMessage(
        item.messageId,
        ChatMessage(
          messageId: item.messageId,
          threadId: threadId,
          senderId: _myUid,
          encryptedText: '',
          sentAt: DateTime.now().toUtc(),
          deletedFor: const [],
          mediaType: MessageType.image,
          mediaRef: 'chat_media/$threadId/${item.messageId}/media.enc',
          mediaMeta: meta,
          localDecryptedText: preview,
          status: MessageStatus.sending,
        ),
      );
      _setUploadStatus(item.messageId, const MediaSendStatus.preparing());
      _queuedBatchIds.add(item.messageId);
    }
    _emitMessages();

    for (final item in items) {
      // Check if user cancelled this item before preparation started
      _queuedBatchIds.remove(item.messageId);
      if (_getPendingMessage(item.messageId) == null) continue;
      try {
        await sendMedia(
          messageId: item.messageId,
          rawBytes: item.bytes,
          type: MessageType.image,
          quality: quality,
          sourceUri: item.sourceUri,
          sourceFlags: item.sourceFlags,
          filename: item.filename,
        );
      } catch (e) {
        debugPrint('Failed to send image ${item.messageId}: $e');
      }
    }
  }

  /// Stages every video in the chat immediately, then prepares and sends them
  /// sequentially to avoid decoding multiple large videos at once.
  Future<void> sendMultipleVideos({
    required List<OutgoingVideoItem> items,
    required VideoQuality quality,
  }) async {
    if (items.isEmpty) return;
    final threadId = _currentThreadId();
    if (threadId == null) return;

    for (final item in items) {
      final preview = ChatMessage.mediaPreviewFor(
        MessageType.video,
        filename: item.filename,
      );
      _setPendingMessage(
        item.messageId,
        ChatMessage(
          messageId: item.messageId,
          threadId: threadId,
          senderId: _myUid,
          encryptedText: '',
          sentAt: DateTime.now().toUtc(),
          deletedFor: const [],
          mediaType: MessageType.video,
          mediaRef: 'chat_media/$threadId/${item.messageId}/media.enc',
          mediaMeta: MediaMeta(sizeBytes: item.bytes.length),
          localDecryptedText: preview,
          status: MessageStatus.sending,
        ),
      );
      _setUploadStatus(item.messageId, const MediaSendStatus.preparing());
      _queuedBatchIds.add(item.messageId);
    }
    _emitMessages();

    for (final item in items) {
      _queuedBatchIds.remove(item.messageId);
      if (_getPendingMessage(item.messageId) == null) continue;
      try {
        await sendMedia(
          messageId: item.messageId,
          rawBytes: item.bytes,
          type: MessageType.video,
          filename: item.filename,
          videoQuality: quality,
          sourceUri: item.sourceUri,
          sourceFlags: item.sourceFlags,
        );
      } catch (error) {
        debugPrint('Failed to send video ${item.messageId}: $error');
      }
    }
  }

  Future<void> dispose() async {
    await _androidUploadSub?.cancel();
    // Do NOT cancel active upload tokens here. Disposing the screen / cubit (e.g. on
    // app lock, navigation, or backgrounding) should NOT abort active uploads or delete
    // staged media files. Only explicit user cancellations (cancelUpload) should cancel them.
  }
}
