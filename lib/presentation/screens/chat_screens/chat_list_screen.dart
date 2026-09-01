import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../../../application/services/chat_notification_service.dart';
import '../../../application/services/chat_vault_bridge.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../core/widgets/main_scaffold_scope.dart';
import '../../state/chat/active_thread_cubit.dart';
import '../../state/chat/chat_auth_cubit.dart';
import '../../state/chat/contact_discovery_cubit.dart';
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
            return const Center(child: CircularProgressIndicator());
          }
          if (state is ThreadListError) {
            return Center(child: Text(state.message));
          }
          if (state is ThreadListLoaded) {
            if (state.items.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.chat_bubble_outline, size: 64),
                    const SizedBox(height: 16),
                    const Text('No conversations yet.'),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Start a chat'),
                      onPressed: () => _openNewChat(context),
                    ),
                  ],
                ),
              );
            }
            return ListView.separated(
              itemCount: state.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = state.items[i];
                final unread = item.thread.unreadCountFor(widget.myUid);
                return Dismissible(
                  key: ValueKey(item.thread.threadId),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.red,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: const Icon(Icons.delete_outline, color: Colors.white),
                  ),
                  confirmDismiss: (_) => _confirmDelete(context),
                  onDismissed: (_) {
                    context
                        .read<ThreadListCubit>()
                        .deleteThread(item.thread.threadId);
                  },
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: _Avatar(
                      user: item.otherUser,
                      isOnline: state.isOnline(item.otherUser.uid),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.otherUser.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          _formatTime(item.thread.lastMessageAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    subtitle: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.thread.lastMessage.isEmpty
                                ? item.otherUser.email
                                : item.thread.lastMessage,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: unread > 0
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        if (state.isOnline(item.otherUser.uid))
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(left: 6),
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (unread > 0)
                          Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$unread',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ),
                      ],
                    ),
                    onTap: () => openThreadScreen(
                      context,
                      thread: item.thread,
                      otherUser: item.otherUser,
                    ),
                  ),
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
    );
  }

  void _openNewChat(BuildContext context) {
    // Carry the chat providers across the root navigator boundary.
    final userLookup = context.read<UserLookupCubit>();
    final contactDiscovery = context.read<ContactDiscoveryCubit>();
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
              BlocProvider.value(value: contactDiscovery),
              BlocProvider.value(value: activeThread),
            ],
            child: const NewChatScreen(),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmDelete(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete chat'),
        content: const Text(
            'Delete this conversation and all its messages? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user, required this.isOnline});
  final ChatUser user;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          backgroundImage: user.photoUrl != null
              ? CachedNetworkImageProvider(user.photoUrl!)
              : null,
          child: user.photoUrl == null
              ? Text(user.initials,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer))
              : null,
        ),
        if (isOnline)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}
