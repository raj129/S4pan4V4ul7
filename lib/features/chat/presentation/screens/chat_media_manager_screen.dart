import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_state_views.dart';
import '../../application/media/chat_media_loader.dart';
import '../../domain/entities/chat_media_item.dart';
import '../../application/media/chat_media_manager_service.dart';
import '../state/chat_media_manager_cubit.dart';
import 'chat_image_viewer_screen.dart';
import 'chat_video_player_screen.dart';

Future<void> openChatMediaManager(
  BuildContext context, {
  required ChatMediaManagerService service,
  required ChatMediaLoader mediaLoader,
  required String currentUid,
  String? threadId,
  String title = 'Manage Media',
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider(
        create: (_) => ChatMediaManagerCubit(
          service: service,
          currentUid: currentUid,
          threadId: threadId,
        )..loadMedia(),
        child: ChatMediaManagerScreen(mediaLoader: mediaLoader, title: title),
      ),
    ),
  );
}

class ChatMediaManagerScreen extends StatelessWidget {
  const ChatMediaManagerScreen({
    super.key,
    required this.mediaLoader,
    this.title = 'Manage Media',
  });

  final ChatMediaLoader mediaLoader;
  final String title;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatMediaManagerCubit, ChatMediaManagerState>(
      builder: (context, state) {
        if (state is ChatMediaManagerLoading) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const LoadingView(message: 'Loading media…'),
          );
        }

        if (state is ChatMediaManagerError) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: ErrorView(
              message: state.message,
              onRetry: () => context.read<ChatMediaManagerCubit>().loadMedia(),
            ),
          );
        }

        if (state is! ChatMediaManagerLoaded) {
          return Scaffold(
            appBar: AppBar(title: Text(title)),
            body: const SizedBox.shrink(),
          );
        }

        final cubit = context.read<ChatMediaManagerCubit>();
        final hasSelection = state.selectedIds.isNotEmpty;

        return Scaffold(
          appBar: AppBar(
            title: Text(
              hasSelection ? '${state.selectedIds.length} selected' : title,
            ),
            actions: [
              if (hasSelection) ...[
                IconButton(
                  tooltip: 'Select all',
                  icon: const Icon(Icons.select_all_rounded),
                  onPressed: cubit.selectAllFiltered,
                ),
                IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: cubit.clearSelection,
                ),
              ] else ...[
                PopupMenuButton<ChatMediaSortOrder>(
                  icon: const Icon(Icons.sort_rounded),
                  tooltip: 'Sort by',
                  initialValue: state.sortOrder,
                  onSelected: cubit.setSortOrder,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: ChatMediaSortOrder.sizeDescending,
                      child: Text('Size (Largest first)'),
                    ),
                    PopupMenuItem(
                      value: ChatMediaSortOrder.sizeAscending,
                      child: Text('Size (Smallest first)'),
                    ),
                    PopupMenuItem(
                      value: ChatMediaSortOrder.dateDescending,
                      child: Text('Date (Newest first)'),
                    ),
                    PopupMenuItem(
                      value: ChatMediaSortOrder.dateAscending,
                      child: Text('Date (Oldest first)'),
                    ),
                  ],
                ),
              ],
            ],
          ),
          bottomNavigationBar: hasSelection
              ? _buildBottomActionBar(context, state, cubit)
              : null,
          body: Column(
            children: [
              if (state.operationError != null)
                MaterialBanner(
                  content: Text(
                    'Some media could not be removed: ${state.operationError}',
                  ),
                  leading: const Icon(Icons.error_outline_rounded),
                  actions: [
                    TextButton(
                      onPressed: () => cubit.loadMedia(),
                      child: const Text('Refresh'),
                    ),
                  ],
                ),
              _buildStorageBreakdownHeader(context, state),
              _buildCategoryChips(context, state, cubit),
              const Divider(height: 1),
              Expanded(
                child: state.filteredItems.isEmpty
                    ? const EmptyView(
                        icon: Icons.perm_media_outlined,
                        title: 'No media found',
                        subtitle: 'No attachments match the selected category.',
                      )
                    : _buildMediaGrid(context, state, cubit),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStorageBreakdownHeader(
    BuildContext context,
    ChatMediaManagerLoaded state,
  ) {
    final theme = Theme.of(context);
    final totalFormatted = _formatBytes(state.totalCachedBytes);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.pie_chart_outline_rounded,
                size: 20,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                'Cached on this device: $totalFormatted',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '${state.allItems.length} items',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildStorageBar(context, state),
        ],
      ),
    );
  }

  Widget _buildStorageBar(BuildContext context, ChatMediaManagerLoaded state) {
    final total = state.totalCachedBytes;
    if (total <= 0) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          height: 8,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
      );
    }

    final bytesMap = state.bytesByCategory;
    int flexFor(ChatMediaCategory category) =>
        ((bytesMap[category] ?? 0) / total * 1000)
            .round()
            .clamp(1, 1000)
            .toInt();
    final photosFlex = bytesMap[ChatMediaCategory.photos] == 0
        ? 0
        : flexFor(ChatMediaCategory.photos);
    final videosFlex = bytesMap[ChatMediaCategory.videos] == 0
        ? 0
        : flexFor(ChatMediaCategory.videos);
    final audioFlex = bytesMap[ChatMediaCategory.audio] == 0
        ? 0
        : flexFor(ChatMediaCategory.audio);
    final docsFlex = bytesMap[ChatMediaCategory.documents] == 0
        ? 0
        : flexFor(ChatMediaCategory.documents);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 8,
        child: Row(
          children: [
            if (photosFlex > 0)
              Expanded(
                flex: photosFlex,
                child: Container(color: Colors.purpleAccent),
              ),
            if (videosFlex > 0)
              Expanded(
                flex: videosFlex,
                child: Container(color: Colors.blueAccent),
              ),
            if (audioFlex > 0)
              Expanded(
                flex: audioFlex,
                child: Container(color: Colors.orangeAccent),
              ),
            if (docsFlex > 0)
              Expanded(
                flex: docsFlex,
                child: Container(color: Colors.tealAccent.shade700),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChips(
    BuildContext context,
    ChatMediaManagerLoaded state,
    ChatMediaManagerCubit cubit,
  ) {
    final categories = [
      (ChatMediaCategory.all, 'All', Icons.apps_rounded),
      (ChatMediaCategory.photos, 'Photos', Icons.photo_rounded),
      (ChatMediaCategory.videos, 'Videos', Icons.videocam_rounded),
      (ChatMediaCategory.audio, 'Audio', Icons.audiotrack_rounded),
      (ChatMediaCategory.documents, 'Docs', Icons.insert_drive_file_rounded),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: categories.map((cat) {
          final isSelected = state.selectedCategory == cat.$1;
          final count = cat.$1 == ChatMediaCategory.all
              ? state.allItems.length
              : (state.countByCategory[cat.$1] ?? 0);

          return Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: FilterChip(
              avatar: Icon(cat.$3, size: 16),
              label: Text('${cat.$2} ($count)'),
              selected: isSelected,
              onSelected: (_) => cubit.setCategory(cat.$1),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMediaGrid(
    BuildContext context,
    ChatMediaManagerLoaded state,
    ChatMediaManagerCubit cubit,
  ) {
    final items = state.filteredItems;

    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1.0,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final isSelected = state.selectedIds.contains(item.messageId);

        return _MediaItemTile(
          item: item,
          isSelected: isSelected,
          onTap: () {
            if (state.selectedIds.isNotEmpty) {
              cubit.toggleSelection(item.messageId);
            } else {
              _openItem(context, item);
            }
          },
          onLongPress: () => cubit.toggleSelection(item.messageId),
        );
      },
    );
  }

  void _openItem(BuildContext context, ChatMediaItem item) {
    if (item.category == ChatMediaCategory.photos) {
      ChatImageViewerScreen.open(
        context,
        message: item.message,
        loader: mediaLoader,
      );
    } else if (item.category == ChatMediaCategory.videos) {
      ChatVideoPlayerScreen.open(
        context,
        message: item.message,
        loader: mediaLoader,
      );
    } else {
      showDialog<void>(
        context: context,
        builder: (dialogCtx) => AlertDialog(
          title: Text(item.displayName ?? 'Attachment'),
          content: Text(
            'Size: ${item.readableSize}\nSent: ${DateFormat.yMMMd().add_jm().format(item.sentAt.toLocal())}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildBottomActionBar(
    BuildContext context,
    ChatMediaManagerLoaded state,
    ChatMediaManagerCubit cubit,
  ) {
    final theme = Theme.of(context);
    final count = state.selectedIds.length;
    final sizeFormatted = _formatBytes(state.selectedCachedBytes);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count items selected',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Clears $sizeFormatted cached',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const Spacer(),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(state.isDeleting ? 'Removing…' : 'Remove ($count)'),
              onPressed: state.isDeleting
                  ? null
                  : () => _confirmDelete(context, cubit, count, sizeFormatted),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ChatMediaManagerCubit cubit,
    int count,
    String sizeFormatted,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Remove media for me?'),
        content: Text(
          'Remove $count selected items from your copy of the chat and clear their local cached files? '
          'This will clear $sizeFormatted of cached data from this device. Other participants can still see the messages and media.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogCtx).colorScheme.error,
              foregroundColor: Theme.of(dialogCtx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Remove for me'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await cubit.deleteSelected();
      if (context.mounted) {
        final result = cubit.state;
        if (result is ChatMediaManagerLoaded && result.operationError == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Removed $count items ($sizeFormatted cached cleared).',
              ),
            ),
          );
        }
      }
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _MediaItemTile extends StatelessWidget {
  const _MediaItemTile({
    required this.item,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  final ChatMediaItem item;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: _buildThumbnail(context),
          ),
          // Size badge at the bottom right
          Positioned(
            right: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                item.readableSize,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          // Category icon indicator at the bottom left
          Positioned(
            left: 4,
            bottom: 4,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconForCategory(item.category),
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
          // Selection overlay
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: theme.colorScheme.primary.withValues(alpha: 0.35),
                border: Border.all(
                  color: theme.colorScheme.primary,
                  width: 2.5,
                ),
              ),
              child: const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(4),
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.check, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final category = item.category;
    final isAudio = category == ChatMediaCategory.audio;
    final isDocument = category == ChatMediaCategory.documents;
    final color = switch (category) {
      ChatMediaCategory.photos => Colors.purpleAccent,
      ChatMediaCategory.videos => Colors.blueAccent,
      ChatMediaCategory.audio => Colors.orangeAccent,
      ChatMediaCategory.documents => Colors.tealAccent,
      ChatMediaCategory.all => Colors.grey,
    };
    return Container(
      color: color.withValues(alpha: 0.18),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isAudio
                ? Icons.audiotrack_rounded
                : isDocument
                ? Icons.description_rounded
                : category == ChatMediaCategory.videos
                ? Icons.videocam_rounded
                : Icons.photo_rounded,
            size: 32,
            color: color,
          ),
          const SizedBox(height: 4),
          Text(
            item.displayName ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _iconForCategory(ChatMediaCategory cat) => switch (cat) {
    ChatMediaCategory.photos => Icons.photo,
    ChatMediaCategory.videos => Icons.videocam,
    ChatMediaCategory.audio => Icons.mic,
    ChatMediaCategory.documents => Icons.insert_drive_file,
    ChatMediaCategory.all => Icons.attach_file,
  };
}
