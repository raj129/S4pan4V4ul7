import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_media_item.dart';
import '../../domain/repositories/message_cache_repository.dart';
import '../../domain/repositories/message_repository.dart';
import 'chat_media_loader.dart';

class ChatMediaManagerService {
  ChatMediaManagerService({
    required this.messageCache,
    required this.messageRepository,
    required this.mediaLoader,
  });

  final MessageCacheRepository messageCache;
  final MessageRepository messageRepository;
  final ChatMediaLoader mediaLoader;

  /// Loads media items for a specific thread, or across all cached threads when threadId is null.
  Future<List<ChatMediaItem>> loadMedia({
    String? threadId,
    required String currentUid,
  }) async {
    _checkAccount(currentUid);
    final messages = threadId == null
        ? [
            for (final record in await messageCache.exportAll())
              if (CachedMessageCodec.decode(record.payloadJson)
                  case final ChatMessage message)
                message,
          ]
        : await messageCache.loadAll(threadId);

    final List<ChatMediaItem> items = [];
    for (final msg in messages) {
      if (msg.mediaRef != null &&
          ChatMediaItem.categorize(msg.mediaType) != ChatMediaCategory.all &&
          !msg.isDeletedFor(currentUid)) {
        final attachmentBytes = await mediaLoader.cachedSize(msg.mediaRef!);
        final thumbnailRef = msg.mediaMeta?.thumbRef;
        final thumbnailBytes = thumbnailRef == null
            ? 0
            : await mediaLoader.cachedSize(thumbnailRef);
        items.add(
          ChatMediaItem.fromMessage(
            msg,
            cachedBytes: attachmentBytes + thumbnailBytes,
          ),
        );
      }
    }

    return items;
  }

  /// Deletes selected media items for the current user and frees disk space.
  Future<void> deleteMediaItems({
    required List<ChatMediaItem> items,
    required String currentUid,
  }) async {
    _checkAccount(currentUid);
    for (final item in items) {
      final msg = item.message;
      final storagePath = msg.mediaRef;

      if (storagePath == null) continue;

      // Keep deletion scoped to this user; the remote object stays available
      // to other participants in the conversation.
      await messageRepository.deleteMessageForUser(
        threadId: msg.threadId,
        messageId: msg.messageId,
        uid: currentUid,
      );

      final updated = msg.copyWith(
        deletedFor: {...msg.deletedFor, currentUid}.toList(),
      );
      await messageCache.save([updated]);

      await mediaLoader.removeLocal(storagePath);
      final thumbPath = msg.mediaMeta?.thumbRef;
      if (thumbPath != null && thumbPath != storagePath) {
        await mediaLoader.removeLocal(thumbPath);
      }
    }
  }

  void _checkAccount(String currentUid) {
    if (currentUid.isEmpty || mediaLoader.accountId != currentUid) {
      throw StateError(
        'The signed-in chat account changed. Reopen media management.',
      );
    }
  }
}
