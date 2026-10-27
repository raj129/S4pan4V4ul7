import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/chat_media_item.dart';
import '../../application/media/chat_media_manager_service.dart';

sealed class ChatMediaManagerState extends Equatable {
  const ChatMediaManagerState();

  @override
  List<Object?> get props => [];
}

class ChatMediaManagerLoading extends ChatMediaManagerState {
  const ChatMediaManagerLoading();
}

class ChatMediaManagerLoaded extends ChatMediaManagerState {
  const ChatMediaManagerLoaded({
    required this.allItems,
    this.selectedCategory = ChatMediaCategory.all,
    this.sortOrder = ChatMediaSortOrder.sizeDescending,
    this.selectedIds = const {},
    this.isDeleting = false,
    this.operationError,
  });

  final List<ChatMediaItem> allItems;
  final ChatMediaCategory selectedCategory;
  final ChatMediaSortOrder sortOrder;
  final Set<String> selectedIds;
  final bool isDeleting;
  final String? operationError;

  /// Filtered items based on active category
  List<ChatMediaItem> get filteredItems {
    final list = selectedCategory == ChatMediaCategory.all
        ? allItems
        : allItems.where((i) => i.category == selectedCategory).toList();

    return [...list]..sort((a, b) {
      return switch (sortOrder) {
        ChatMediaSortOrder.sizeDescending => b.sizeBytes.compareTo(a.sizeBytes),
        ChatMediaSortOrder.sizeAscending => a.sizeBytes.compareTo(b.sizeBytes),
        ChatMediaSortOrder.dateDescending => b.sentAt.compareTo(a.sentAt),
        ChatMediaSortOrder.dateAscending => a.sentAt.compareTo(b.sentAt),
      };
    });
  }

  /// Locally cached ciphertext that removing these chat items can reclaim.
  int get totalCachedBytes =>
      allItems.fold(0, (acc, item) => acc + item.cachedBytes);

  /// Total bytes for currently selected items
  int get selectedCachedBytes => allItems
      .where((item) => selectedIds.contains(item.messageId))
      .fold(0, (acc, item) => acc + item.cachedBytes);

  /// Bytes per category breakdown
  Map<ChatMediaCategory, int> get bytesByCategory {
    final map = <ChatMediaCategory, int>{
      ChatMediaCategory.photos: 0,
      ChatMediaCategory.videos: 0,
      ChatMediaCategory.audio: 0,
      ChatMediaCategory.documents: 0,
    };
    for (final item in allItems) {
      map[item.category] = (map[item.category] ?? 0) + item.cachedBytes;
    }
    return map;
  }

  /// Count per category breakdown
  Map<ChatMediaCategory, int> get countByCategory {
    final map = <ChatMediaCategory, int>{
      ChatMediaCategory.photos: 0,
      ChatMediaCategory.videos: 0,
      ChatMediaCategory.audio: 0,
      ChatMediaCategory.documents: 0,
    };
    for (final item in allItems) {
      map[item.category] = (map[item.category] ?? 0) + 1;
    }
    return map;
  }

  ChatMediaManagerLoaded copyWith({
    List<ChatMediaItem>? allItems,
    ChatMediaCategory? selectedCategory,
    ChatMediaSortOrder? sortOrder,
    Set<String>? selectedIds,
    bool? isDeleting,
    String? operationError,
    bool clearOperationError = false,
  }) {
    return ChatMediaManagerLoaded(
      allItems: allItems ?? this.allItems,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      sortOrder: sortOrder ?? this.sortOrder,
      selectedIds: selectedIds ?? this.selectedIds,
      isDeleting: isDeleting ?? this.isDeleting,
      operationError: clearOperationError
          ? null
          : operationError ?? this.operationError,
    );
  }

  @override
  List<Object?> get props => [
    allItems,
    selectedCategory,
    sortOrder,
    selectedIds,
    isDeleting,
    operationError,
  ];
}

class ChatMediaManagerError extends ChatMediaManagerState {
  const ChatMediaManagerError(this.message);
  final String message;

  @override
  List<Object?> get props => [message];
}

class ChatMediaManagerCubit extends Cubit<ChatMediaManagerState> {
  ChatMediaManagerCubit({
    required this.service,
    required this.currentUid,
    this.threadId,
  }) : super(const ChatMediaManagerLoading());

  final ChatMediaManagerService service;
  final String currentUid;
  final String? threadId;

  Future<void> loadMedia() async {
    emit(const ChatMediaManagerLoading());
    try {
      final items = await service.loadMedia(
        threadId: threadId,
        currentUid: currentUid,
      );
      emit(ChatMediaManagerLoaded(allItems: items));
    } catch (e) {
      emit(ChatMediaManagerError(e.toString()));
    }
  }

  void setCategory(ChatMediaCategory category) {
    final curr = state;
    if (curr is! ChatMediaManagerLoaded) return;
    emit(curr.copyWith(selectedCategory: category));
  }

  void setSortOrder(ChatMediaSortOrder order) {
    final curr = state;
    if (curr is! ChatMediaManagerLoaded) return;
    emit(curr.copyWith(sortOrder: order));
  }

  void toggleSelection(String messageId) {
    final curr = state;
    if (curr is! ChatMediaManagerLoaded) return;
    final updated = Set<String>.from(curr.selectedIds);
    if (updated.contains(messageId)) {
      updated.remove(messageId);
    } else {
      updated.add(messageId);
    }
    emit(curr.copyWith(selectedIds: updated));
  }

  void selectAllFiltered() {
    final curr = state;
    if (curr is! ChatMediaManagerLoaded) return;
    final filtered = curr.filteredItems;
    final updated = Set<String>.from(curr.selectedIds)
      ..addAll(filtered.map((e) => e.messageId));
    emit(curr.copyWith(selectedIds: updated));
  }

  void clearSelection() {
    final curr = state;
    if (curr is! ChatMediaManagerLoaded) return;
    emit(curr.copyWith(selectedIds: const {}));
  }

  Future<void> deleteSelected() async {
    final curr = state;
    if (curr is! ChatMediaManagerLoaded || curr.selectedIds.isEmpty) return;

    final toDelete = curr.allItems
        .where((i) => curr.selectedIds.contains(i.messageId))
        .toList();

    emit(curr.copyWith(isDeleting: true, clearOperationError: true));

    try {
      await service.deleteMediaItems(items: toDelete, currentUid: currentUid);

      final remaining = curr.allItems
          .where((i) => !curr.selectedIds.contains(i.messageId))
          .toList();

      emit(
        curr.copyWith(
          allItems: remaining,
          selectedIds: const {},
          isDeleting: false,
          clearOperationError: true,
        ),
      );
    } catch (error) {
      emit(curr.copyWith(isDeleting: false, operationError: error.toString()));
    }
  }
}
