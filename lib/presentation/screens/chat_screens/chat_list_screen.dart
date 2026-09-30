import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../application/services/chat_notification_service.dart';
import '../../../application/services/chat_share_inbox.dart';
import '../../../application/services/profile_service.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../core/widgets/main_scaffold_scope.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../state/chat/active_thread_cubit.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../state/chat/chat_auth_cubit.dart';
import '../../state/chat/thread_list_cubit.dart';
import '../../state/chat/user_lookup_cubit.dart';
import '../../widgets/chat/history_locked_banner.dart';
import '../../widgets/chat/user_avatar.dart';
import 'new_chat_screen.dart';
import 'thread_screen.dart';

/// Main chat list: all conversations for the signed-in user.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key, required this.myUid, this.profileService});

  final String myUid;

  /// Own profile and contact nicknames; without it real names are shown.
  final ProfileService? profileService;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  ChatNotificationService? _notifications;
  ProfileService? get _profile => widget.profileService;

  @override
  void initState() {
    super.initState();
    context.read<ThreadListCubit>().startWatching();
    try {
      _notifications = context.read<ChatNotificationService>();
      _notifications!.pendingThreadId.addListener(_openPendingThread);
    } catch (_) {
      // Not provided (tests); notification taps simply are not routed.
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingThread());
  }

  @override
  void dispose() {
    _notifications?.pendingThreadId.removeListener(_openPendingThread);
    super.dispose();
  }

  /// Open the conversation of a tapped notification.
  ///
  /// Runs here rather than at tap time because this screen only exists once
  /// the vault is unlocked and chat is signed in, so a tap cannot skip the PIN.
  void _openPendingThread() {
    if (!mounted) return;
    final notifications = _notifications;
    final pending = notifications?.pendingThreadId.value;
    if (notifications == null || pending == null) return;
    final state = context.read<ThreadListCubit>().state;
    if (state is! ThreadListLoaded) return;
    notifications.takePendingThread();
    if (notifications.isActiveThread(pending)) return;
    for (final item in state.items) {
      if (item.thread.threadId == pending) {
        openThreadScreen(
          context,
          thread: item.thread,
          otherUser: item.otherUser,
        );
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ThreadListCubit, ThreadListState>(
      listenWhen: (prev, next) =>
          prev is! ThreadListLoaded && next is ThreadListLoaded,
      listener: (_, _) => _openPendingThread(),
      child: _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chats'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => openAppNavigationDrawer(context),
        ),
        actions: [
          if (_profile != null)
            IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'My profile',
              onPressed: () {
                final auth = context.read<ChatAuthCubit>().state;
                if (auth is ChatAuthAuthenticated) {
                  context.push('/chat/profile', extra: auth.user);
                }
              },
            ),
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
          ListenableBuilder(
            listenable: ChatShareInbox.instance,
            builder: (context, _) {
              final inbox = ChatShareInbox.instance;
              if (!inbox.hasPending) return const SizedBox.shrink();
              return _ShareBanner(
                count: inbox.count,
                onCancel: inbox.clear,
              );
            },
          ),
          Expanded(child: _buildThreadList(context)),
        ],
      ),
    );
  }

  Widget _buildThreadList(BuildContext context) {
    final profile = _profile;
    if (profile == null) return _buildThreads(context, null);
    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) => _buildThreads(context, profile),
    );
  }

  Widget _buildThreads(BuildContext context, ProfileService? profile) {
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
              name:
                  profile?.nameFor(item.otherUser) ??
                  item.otherUser.displayName,
              isOnline: state.isOnline(item.otherUser.uid),
              unread: unread,
              lastMessage:
                  item.thread.lastMessage.isEmpty &&
                      !item.thread.lastMessageAt.isAfter(item.thread.createdAt)
                  ? 'No messages yet'
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
    UserLookupCubit? userLookup;
    ActiveThreadCubit? activeThread;
    try {
      userLookup = context.read<UserLookupCubit>();
    } catch (_) {}
    try {
      activeThread = context.read<ActiveThreadCubit>();
    } catch (_) {}
    context.push(
      '/chat/new',
      extra: NewChatArgs(
        userLookupCubit: userLookup,
        activeThreadCubit: activeThread,
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
    required this.name,
    required this.isOnline,
    required this.unread,
    required this.lastMessage,
    required this.timeLabel,
    required this.onTap,
    required this.onConfirmDelete,
    required this.onDelete,
  });

  final ChatUser user;
  final String name;
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
          child: Icon(Icons.delete_outline_rounded, color: cs.onErrorContainer),
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
                  _Avatar(user: user, name: name, isOnline: isOnline),
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
                                name,
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
  const _Avatar({
    required this.user,
    required this.name,
    required this.isOnline,
  });
  final ChatUser user;
  final String name;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        children: [
          UserAvatar(avatar: user.avatar, name: name),
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

/// Prompt shown while files shared from another app wait for a recipient.
class _ShareBanner extends StatelessWidget {
  const _ShareBanner({required this.count, required this.onCancel});

  final int count;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.primaryContainer,
      child: ListTile(
        leading: Icon(Icons.send_rounded, color: cs.onPrimaryContainer),
        title: Text(
          count == 1
              ? 'Choose a chat to send 1 file'
              : 'Choose a chat to send $count files',
          style: TextStyle(color: cs.onPrimaryContainer),
        ),
        trailing: TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ),
    );
  }
}
