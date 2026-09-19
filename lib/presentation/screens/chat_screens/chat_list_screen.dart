import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../application/services/chat_notification_service.dart';
import '../../../application/services/chat_vault_bridge.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../core/widgets/main_scaffold_scope.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../state/chat/active_thread_cubit.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../state/chat/chat_auth_cubit.dart';
import '../../state/chat/thread_list_cubit.dart';
import '../../state/chat/user_lookup_cubit.dart';
import '../../widgets/chat/chat_media_preview.dart';
import '../../widgets/chat/history_locked_banner.dart';
import 'new_chat_screen.dart';
import 'thread_screen.dart';

/// Main chat list: all conversations for the signed-in user.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.myUid});

  final String myUid;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    context.read<ThreadListCubit>().startWatching();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => openAppNavigationDrawer(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'New chat',
            onPressed: () => _openNewChat(context),
          ),
        ],
      ),
      body: Column(
        children: [
          BlocBuilder<ChatAuthCubit, ChatAuthState>(
            builder: (context, authState) {
              if (authState is ChatAuthAuthenticated &&
                  authState.historyLocked) {
                return HistoryLockedBanner(result: authState.identitySync!);
              }
              return const SizedBox.shrink();
            },
          ),
          Expanded(child: _buildThreadList(context)),
        ],
      ),
    );
  }

  Widget _buildThreadList(BuildContext context) {
    return BlocBuilder<ThreadListCubit, ThreadListState>(
      builder: (context, state) {
        if (state is ThreadListLoading) {
          return const _ThreadListSkeleton();
        }
        if (state is ThreadListError) {
          return ErrorView(
            message: state.message,
            onRetry: () => context.read<ThreadListCubit>().startWatching(),
          );
        }
        if (state is! ThreadListLoaded) return const SizedBox.shrink();

        if (state.items.isEmpty) {
          return EmptyView(
            icon: Icons.forum_outlined,
            title: 'No conversations yet',
            subtitle:
                'Start an end-to-end encrypted chat — messages and media never '
                'leave this device unprotected.',
            actionLabel: 'Start a chat',
            actionIcon: Icons.add_rounded,
            onAction: () => _openNewChat(context),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          itemCount: state.items.length,
          itemBuilder: (context, i) {
            final item = state.items[i];
            final unread = item.thread.unreadCountFor(widget.myUid);
            return _ThreadTile(
              key: ValueKey(item.thread.threadId),
              user: item.otherUser,
              isOnline: state.isOnline(item.otherUser.uid),
              unread: unread,
              lastMessage: item.thread.lastMessage.isEmpty
                  ? item.otherUser.email
                  : item.thread.lastMessage,
              timeLabel: _formatTime(item.thread.lastMessageAt),
              onTap: () => openThreadScreen(
                context,
                thread: item.thread,
                otherUser: item.otherUser,
              ),
              onConfirmDelete: () => _confirmDelete(context),
              onDelete: () => context.read<ThreadListCubit>().deleteThread(
                item.thread.threadId,
              ),
            );
          },
        );
      },
    );
  }

  void _openNewChat(BuildContext context) {
    // Carry the chat providers across the root navigator boundary.
    final userLookup = context.read<UserLookupCubit>();
    final activeThread = context.read<ActiveThreadCubit>();
    final mediaLoader = context.read<ChatMediaLoader>();
    final vaultBridge = context.read<ChatVaultBridge>();
    final notifications = context.read<ChatNotificationService>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ChatMediaLoader>.value(value: mediaLoader),
            RepositoryProvider<ChatVaultBridge>.value(value: vaultBridge),
            RepositoryProvider<ChatNotificationService>.value(
              value: notifications,
            ),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider.value(value: userLookup),
              BlocProvider.value(value: activeThread),
            ],
            child: const NewChatScreen(),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.delete_outline_rounded, color: cs.error),
        title: const Text('Delete chat'),
        content: const Text(
          'Delete this conversation and all its messages? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.onErrorContainer,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final local = dt.toLocal();
    if (now.difference(local).inDays == 0) {
      return DateFormat.jm().format(local);
    }
    if (now.difference(local).inDays < 7) {
      return DateFormat.E().format(local);
    }
    return DateFormat.yMd().format(local);
  }
}

/// A single conversation row: swipe-to-delete, unread emphasis, presence dot.
class _ThreadTile extends StatelessWidget {
  const _ThreadTile({
    super.key,
    required this.user,
    required this.isOnline,
    required this.unread,
    required this.lastMessage,
    required this.timeLabel,
    required this.onTap,
    required this.onConfirmDelete,
    required this.onDelete,
  });

  final ChatUser user;
  final bool isOnline;
  final int unread;
  final String lastMessage;
  final String timeLabel;
  final VoidCallback onTap;
  final Future<bool?> Function() onConfirmDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasUnread = unread > 0;
    final radius = AppRadius.all(AppRadius.lg);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Dismissible(
        key: ValueKey('dismiss_${user.uid}'),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: radius,
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: cs.onErrorContainer,
          ),
        ),
        confirmDismiss: (_) => onConfirmDelete(),
        onDismissed: (_) => onDelete(),
        child: Material(
          // Unread rows sit on a faint tint so they stand out in a long list.
          color: hasUnread
              ? cs.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm + AppSpacing.xxs,
              ),
              child: Row(
                children: [
                  _Avatar(user: user, isOnline: isOnline),
                  const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                user.displayName,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: hasUnread
                                      ? FontWeight.w700
                                      : FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              timeLabel,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: hasUnread
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                                fontWeight: hasUnread
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lastMessage,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: hasUnread
                                      ? cs.onSurface
                                      : cs.onSurfaceVariant,
                                  fontWeight: hasUnread
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                            if (hasUnread) ...[
                              const SizedBox(width: AppSpacing.sm),
                              _UnreadBadge(count: unread),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadBadge extends StatelessWidget {
  const _UnreadBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: AppRadius.all(AppRadius.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Placeholder rows shown while the first thread snapshot is in flight.
class _ThreadListSkeleton extends StatelessWidget {
  const _ThreadListSkeleton();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final block = cs.onSurface.withValues(alpha: 0.06);
    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.sm),
      itemCount: 7,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm + AppSpacing.xxs,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: block, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 12,
                    width: 140.0 - (i % 3) * 24,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: AppRadius.all(AppRadius.xs),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: block,
                      borderRadius: AppRadius.all(AppRadius.xs),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.isOnline});
  final ChatUser user;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: cs.primaryContainer,
            backgroundImage: user.photoUrl != null
                ? CachedNetworkImageProvider(user.photoUrl!)
                : null,
            child: user.photoUrl == null
                ? Text(
                    user.initials,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : null,
          ),
          if (isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  color: context.semantic.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
