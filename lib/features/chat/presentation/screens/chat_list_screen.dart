import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../application/services/chat_notification_service.dart';
import '../../application/media/chat_share_inbox.dart';
import '../../application/services/profile_service.dart';
import '../../application/services/arrival_alert_service.dart';
import '../../application/services/saved_places_service.dart';
import 'my_locations_screen.dart';
import '../../domain/entities/chat_user.dart';
import 'package:photo_vault/core/widgets/main_scaffold_scope.dart';
import 'package:photo_vault/core/widgets/app_state_views.dart';
import '../state/active_thread_cubit.dart';
import 'package:photo_vault/core/presentation/theme/app_colors.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../state/chat_auth_cubit.dart';
import '../state/thread_list_cubit.dart';
import '../state/user_lookup_cubit.dart';
import '../widgets/history_locked_banner.dart';
import '../widgets/user_avatar.dart';
import 'new_chat_screen.dart';
import 'thread_screen.dart';

/// Main chat list: all conversations for the signed-in user.
class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
    required this.myUid,
    this.profileService,
    this.placesService,
    this.arrivalService,
    this.sendGeoShare,
  });

  final String myUid;

  /// Own profile and contact nicknames; without it real names are shown.
  final ProfileService? profileService;

  /// Saved places and arrival alerts; the "My locations" action only shows
  /// when all three are provided (Android).
  final SavedPlacesService? placesService;
  final ArrivalAlertService? arrivalService;
  final SendGeoShare? sendGeoShare;

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  ChatNotificationService? _notifications;
  ProfileService? get _profile => widget.profileService;
  bool _isSearching = false;
  bool _unreadOnly = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    context.read<ThreadListCubit>().startWatching();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
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
    _searchController.dispose();
    _searchFocusNode.dispose();
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

  void _openMyLocations() {
    final places = widget.placesService;
    final arrivals = widget.arrivalService;
    final send = widget.sendGeoShare;
    if (places == null || arrivals == null || send == null) return;
    final cubit = context.read<ThreadListCubit>();
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MyLocationsScreen(
          myUid: widget.myUid,
          placesService: places,
          arrivalService: arrivals,
          sendGeoShare: send,
          contacts: () => switch (cubit.state) {
            ThreadListLoaded(:final items) => items,
            _ => const [],
          },
          nameOf: (user) => _profile?.nameFor(user) ?? user.displayName,
        ),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: 'Search conversations…',
                  hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  filled: false,
                ),
              )
            : const Text('Chats'),
        leading: _isSearching
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _isSearching = false;
                    _searchController.clear();
                  });
                },
              )
            : IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () => openAppNavigationDrawer(context),
              ),
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close_rounded),
              tooltip: 'Clear',
              onPressed: () => _searchController.clear(),
            )
          else ...[
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: 'Search',
              onPressed: () => setState(() => _isSearching = true),
            ),
            if (widget.placesService != null &&
                widget.arrivalService != null &&
                widget.sendGeoShare != null)
              IconButton(
                icon: const Icon(Icons.pin_drop_outlined),
                tooltip: 'My locations',
                onPressed: _openMyLocations,
              ),
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'chat_list_new_chat_fab',
        tooltip: 'Start new conversation',
        onPressed: () => _openNewChat(context),
        child: const Icon(Icons.add_comment_rounded),
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
              return _ShareBanner(count: inbox.count, onCancel: inbox.clear);
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

        final totalUnread = state.items.fold<int>(
          0,
          (sum, item) => sum + item.thread.unreadCountFor(widget.myUid),
        );

        final filteredItems = state.items.where((item) {
          if (_unreadOnly && item.thread.unreadCountFor(widget.myUid) <= 0) {
            return false;
          }
          if (_searchQuery.isEmpty) return true;
          final name =
              (profile?.nameFor(item.otherUser) ?? item.otherUser.displayName)
                  .toLowerCase();
          final last = item.thread.lastMessage.toLowerCase();
          return name.contains(_searchQuery) || last.contains(_searchQuery);
        }).toList();

        return Column(
          children: [
            _ElementXFilterHeader(
              controller: _searchController,
              focusNode: _searchFocusNode,
              searchQuery: _searchQuery,
              unreadOnly: _unreadOnly,
              totalUnread: totalUnread,
              onUnreadFilterChanged: (val) => setState(() => _unreadOnly = val),
              onClearSearch: _searchController.clear,
            ),
            Expanded(
              child: filteredItems.isEmpty
                  ? EmptyView(
                      icon: _unreadOnly && _searchQuery.isEmpty
                          ? Icons.mark_chat_read_outlined
                          : Icons.search_off_rounded,
                      title: _unreadOnly && _searchQuery.isEmpty
                          ? 'All caught up'
                          : 'No matches found',
                      subtitle: _unreadOnly && _searchQuery.isEmpty
                          ? 'You have no unread conversations.'
                          : 'No conversations match "$_searchQuery".',
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm,
                        AppSpacing.xs,
                        AppSpacing.sm,
                        88,
                      ),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, i) {
                        final item = filteredItems[i];
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
                                  !item.thread.lastMessageAt.isAfter(
                                    item.thread.createdAt,
                                  )
                              ? 'No messages yet'
                              : item.thread.lastMessage,
                          timeLabel: _formatTime(item.thread.lastMessageAt),
                          onTap: () => openThreadScreen(
                            context,
                            thread: item.thread,
                            otherUser: item.otherUser,
                          ),
                          onConfirmDelete: () => _confirmDelete(context),
                          onDelete: () => context
                              .read<ThreadListCubit>()
                              .deleteThread(item.thread.threadId),
                        );
                      },
                    ),
            ),
          ],
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

/// Element X Android style inline pill search bar + All / Unread filter chips.
class _ElementXFilterHeader extends StatelessWidget {
  const _ElementXFilterHeader({
    required this.controller,
    required this.focusNode,
    required this.searchQuery,
    required this.unreadOnly,
    required this.totalUnread,
    required this.onUnreadFilterChanged,
    required this.onClearSearch,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String searchQuery;
  final bool unreadOnly;
  final int totalUnread;
  final ValueChanged<bool> onUnreadFilterChanged;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: AppRadius.all(AppRadius.pill),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: theme.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: 'Filter rooms or messages…',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      filled: false,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                if (searchQuery.isNotEmpty)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: onClearSearch,
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              FilterChip(
                selected: !unreadOnly,
                showCheckmark: false,
                label: const Text('All'),
                onSelected: (_) => onUnreadFilterChanged(false),
              ),
              const SizedBox(width: AppSpacing.sm),
              FilterChip(
                selected: unreadOnly,
                showCheckmark: false,
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Unread'),
                    if (totalUnread > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          borderRadius: AppRadius.all(AppRadius.pill),
                        ),
                        child: Text(
                          '$totalUnread',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                onSelected: (_) => onUnreadFilterChanged(!unreadOnly),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A single conversation row: Element X room row with 52dp avatar, bold title,
/// single-line preview, right-aligned time and flat tonal unread badge.
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
    final radius = AppRadius.all(AppRadius.md);

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
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
          color: hasUnread
              ? cs.primary.withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm + 2,
              ),
              child: Row(
                children: [
                  _Avatar(user: user, name: name, isOnline: isOnline),
                  const SizedBox(width: AppSpacing.md),
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
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 16,
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
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lastMessage,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 14,
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
      constraints: const BoxConstraints(minWidth: 22, minHeight: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primary,
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: Text(
        count > 99 ? '99+' : '$count',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: cs.onPrimary,
          fontWeight: FontWeight.w700,
          fontSize: 11,
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
      width: 52,
      height: 52,
      child: Stack(
        children: [
          UserAvatar(avatar: user.avatar, name: name, radius: 26),
          if (isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: context.semantic.online,
                  shape: BoxShape.circle,
                  border: Border.all(color: cs.surface, width: 2.2),
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
