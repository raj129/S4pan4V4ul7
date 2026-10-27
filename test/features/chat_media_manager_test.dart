import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_media_item.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/message_metadata.dart';
import 'package:photo_vault/features/chat/presentation/state/chat_media_manager_cubit.dart';

void main() {
  group('ChatMediaItem', () {
    test('categorizes attachment message types', () {
      expect(
        ChatMediaItem.categorize(MessageType.image),
        ChatMediaCategory.photos,
      );
      expect(
        ChatMediaItem.categorize(MessageType.gif),
        ChatMediaCategory.photos,
      );
      expect(
        ChatMediaItem.categorize(MessageType.video),
        ChatMediaCategory.videos,
      );
      expect(
        ChatMediaItem.categorize(MessageType.audio),
        ChatMediaCategory.audio,
      );
      expect(
        ChatMediaItem.categorize(MessageType.file),
        ChatMediaCategory.documents,
      );
      expect(ChatMediaItem.categorize(MessageType.text), ChatMediaCategory.all);
    });

    test('derives display names and formats attachment sizes', () {
      final item = _item(
        id: 'photo',
        type: MessageType.image,
        size: 1536,
        sentAt: DateTime.utc(2025),
      );

      expect(item.displayName, 'Photo');
      expect(item.readableSize, '1.5 KB');
    });
  });

  group('ChatMediaManagerLoaded', () {
    final photo = _item(
      id: 'photo',
      type: MessageType.image,
      size: 2 * 1024 * 1024,
      sentAt: DateTime.utc(2024),
    );
    final video = _item(
      id: 'video',
      type: MessageType.video,
      size: 5 * 1024 * 1024,
      sentAt: DateTime.utc(2025),
    );
    final document = _item(
      id: 'document',
      type: MessageType.file,
      size: 1024,
      sentAt: DateTime.utc(2023),
    );

    test('sorts by size and date in either direction', () {
      var state = ChatMediaManagerLoaded(allItems: [photo, video, document]);
      expect(state.filteredItems.map((item) => item.messageId), [
        'video',
        'photo',
        'document',
      ]);

      state = state.copyWith(sortOrder: ChatMediaSortOrder.sizeAscending);
      expect(state.filteredItems.map((item) => item.messageId), [
        'document',
        'photo',
        'video',
      ]);

      state = state.copyWith(sortOrder: ChatMediaSortOrder.dateAscending);
      expect(state.filteredItems.map((item) => item.messageId), [
        'document',
        'photo',
        'video',
      ]);

      state = state.copyWith(sortOrder: ChatMediaSortOrder.dateDescending);
      expect(state.filteredItems.map((item) => item.messageId), [
        'video',
        'photo',
        'document',
      ]);
    });

    test('filters categories and calculates byte breakdowns', () {
      var state = ChatMediaManagerLoaded(allItems: [photo, video, document]);
      expect(state.totalCachedBytes, 7 * 1024 * 1024 + 1024);
      expect(state.bytesByCategory[ChatMediaCategory.photos], 2 * 1024 * 1024);
      expect(state.countByCategory[ChatMediaCategory.videos], 1);

      state = state.copyWith(selectedCategory: ChatMediaCategory.documents);
      expect(state.filteredItems.map((item) => item.messageId), ['document']);
    });

    test('calculates selected bytes without changing the collection', () {
      final state = ChatMediaManagerLoaded(
        allItems: [photo, video, document],
        selectedIds: const {'photo', 'document'},
      );

      expect(state.selectedCachedBytes, 2 * 1024 * 1024 + 1024);
      expect(state.allItems, [photo, video, document]);
    });
  });
}

ChatMediaItem _item({
  required String id,
  required MessageType type,
  required int size,
  required DateTime sentAt,
}) {
  final message = ChatMessage(
    messageId: id,
    threadId: 'thread',
    senderId: 'sender',
    encryptedText: '',
    sentAt: sentAt,
    deletedFor: const [],
    mediaRef: 'media/$id',
    mediaType: type,
    mediaMeta: MediaMeta(sizeBytes: size),
  );
  return ChatMediaItem.fromMessage(message, cachedBytes: size);
}
