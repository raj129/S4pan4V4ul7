import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:uuid/uuid.dart';

import '../../../application/services/chat_notification_service.dart';
import '../../../application/services/chat_vault_bridge.dart';
import '../../../application/services/image_compressor.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/message_metadata.dart';
import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../state/chat/active_thread_cubit.dart';
import '../../state/chat/thread_list_cubit.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/chat/chat_day_divider.dart';
import '../../widgets/chat/chat_media_preview.dart';
import '../../widgets/chat/chat_scrollbar.dart';
import '../../widgets/chat/chat_wallpaper.dart';
import '../../widgets/chat/image_quality_sheet.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/typing_indicator.dart';
import '../../widgets/chat/vault_picker_sheet.dart';

/// Arguments needed to build [ThreadScreen].
class ChatThreadArgs {
  const ChatThreadArgs({
    required this.thread,
    required this.otherUser,
    this.activeThreadCubit,
    this.threadListCubit,
  });

  final ChatThread thread;
  final ChatUser otherUser;
  final ActiveThreadCubit? activeThreadCubit;

  /// The `/chat/thread` route sits outside ChatApp's providers, so the list
  /// cubit (needed by Clear / Delete) is handed over explicitly.
  final ThreadListCubit? threadListCubit;
}

/// Push the thread screen via declarative routing.
Future<void> openThreadScreen(
  BuildContext context, {
  required ChatThread thread,
  required ChatUser otherUser,
  bool replace = false,
}) {
  ActiveThreadCubit? activeThread;
  try {
    activeThread = context.read<ActiveThreadCubit>();
  } catch (_) {}
  ThreadListCubit? threadList;
  try {
    threadList = context.read<ThreadListCubit>();
  } catch (_) {}
  final args = ChatThreadArgs(
    thread: thread,
    otherUser: otherUser,
    activeThreadCubit: activeThread,
    threadListCubit: threadList,
  );
  if (replace) {
    context.pushReplacement('/chat/thread', extra: args);
    return Future<void>.value();
  } else {
    return context.push('/chat/thread', extra: args);
  }
}

/// The 1:1 chat thread screen.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.thread,
    required this.otherUser,
    required this.mediaLoader,
    required this.vaultBridge,
    required this.onLock,
    this.notificationService,
    this.settingsRepository,
  });

  final ChatThread thread;
  final ChatUser otherUser;

  /// Passed explicitly rather than read from context: this screen is pushed
  /// onto the root navigator, so it sits outside the chat providers.
  final ChatMediaLoader mediaLoader;

  /// Bridge to the photo vault, for attaching and saving media.
  final ChatVaultBridge vaultBridge;
  final VoidCallback onLock;

  /// Told which thread is on screen so it does not notify about it.
  final ChatNotificationService? notificationService;

  /// Remembers the last attachment quality the user chose.
  final SettingsRepository? settingsRepository;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _textCtrl = TextEditingController();
  final _itemScrollCtrl = ItemScrollController();
  final _itemPositions = ItemPositionsListener.create();
  final _picker = ImagePicker();
  final _uuid = const Uuid();
  final _inputFocus = FocusNode();

  bool _showEmojiPicker = false;
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  ChatMessage? _editingMessage;

  bool get _isEditing => _editingMessage != null;

  /// Message flashed after jumping to it from a quote.
  String? _highlightedId;

  /// Rows most recently rendered, so a message id can be mapped to an index.
  List<_ThreadItem> _items = const [];

  /// Drives the send button's reveal without rebuilding the whole composer on
  /// every keystroke.
  final _hasText = ValueNotifier<bool>(false);

  /// Viewport position in the whole cached history (0 first .. 1 latest).
  final _historyPosition = ValueNotifier<double?>(null);
  final _scrollbarVisible = ValueNotifier<bool>(false);
  final _showJumpToLatest = ValueNotifier<bool>(false);
  Timer? _scrollbarHide;
  Timer? _positionThrottle;

  /// Whether the rows in [_items] were built from a detached window.
  bool _renderedDetached = false;

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextControllerChanged);
    context.read<ActiveThreadCubit>().openThread(
      thread: widget.thread,
      otherUser: widget.otherUser,
    );
    _itemPositions.itemPositions.addListener(_onScroll);
    widget.notificationService?.setActiveThread(widget.thread.threadId);
    // Opening the thread is itself a read: everything already on screen counts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ActiveThreadCubit>().markVisibleAsRead();
    });
  }

  void _onTextControllerChanged() {
    _hasText.value = _textCtrl.text.trim().isNotEmpty;
  }

  void _onScroll() {
    final positions = _itemPositions.itemPositions.value;
    if (positions.isEmpty) return;
    final cubit = context.read<ActiveThreadCubit>();
    final indexes = positions.map((p) => p.index);
    final furthest = indexes.reduce((a, b) => a > b ? a : b);
    final nearest = indexes.reduce((a, b) => a < b ? a : b);
    // The list is reversed, so the highest index is the oldest row on screen.
    if (furthest >= _items.length - 3) {
      cubit.loadOlderMessages();
    }
    final state = cubit.state;
    final detached = state is ActiveThreadLoaded && state.isDetached;
    // A detached window pages newer history in as the bottom is approached.
    if (detached && nearest <= 3) cubit.loadNewerMessages();
    _showJumpToLatest.value = detached || nearest > 12;
    _scrollbarVisible.value = true;
    _scrollbarHide?.cancel();
    _scrollbarHide = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) _scrollbarVisible.value = false;
    });
    _scheduleHistoryPosition((nearest + furthest) ~/ 2);
    // Scrolling reveals older messages, which are now read too.
    cubit.markVisibleAsRead();
  }

  /// Refresh the scrollbar thumb from the message around [index], throttled
  /// because it is a (cheap, indexed) database count.
  void _scheduleHistoryPosition(int index) {
    if (_positionThrottle?.isActive ?? false) return;
    _positionThrottle = Timer(const Duration(milliseconds: 250), () async {
      if (!mounted || _items.isEmpty) return;
      ChatMessage? msg;
      for (var i = index.clamp(0, _items.length - 1); i < _items.length; i++) {
        msg = _items[i].message;
        if (msg != null) break;
      }
      if (msg == null) return;
      final pos = await context.read<ActiveThreadCubit>().positionOf(msg);
      if (mounted && pos != null) _historyPosition.value = pos;
    });
  }

  @override
  void dispose() {
    widget.notificationService?.setActiveThread(null);
    _textCtrl.removeListener(_onTextControllerChanged);
    _itemPositions.itemPositions.removeListener(_onScroll);
    _scrollbarHide?.cancel();
    _positionThrottle?.cancel();
    _historyPosition.dispose();
    _scrollbarVisible.dispose();
    _showJumpToLatest.dispose();
    _hasText.dispose();
    _textCtrl.dispose();
    _searchCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocListener(
      listeners: [
        BlocListener<ActiveThreadCubit, ActiveThreadState>(
          listenWhen: (prev, next) {
            final prevErr = prev is ActiveThreadLoaded
                ? prev.actionError
                : null;
            final nextErr = next is ActiveThreadLoaded
                ? next.actionError
                : null;
            return nextErr != null && nextErr != prevErr;
          },
          listener: (context, state) {
            final message = (state as ActiveThreadLoaded).actionError!;
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(message)));
            context.read<ActiveThreadCubit>().clearActionError();
          },
        ),
        BlocListener<ActiveThreadCubit, ActiveThreadState>(
          listenWhen: (prev, next) =>
              next is ActiveThreadLoaded &&
              next.scrollRequest != null &&
              (prev is! ActiveThreadLoaded ||
                  prev.scrollRequest != next.scrollRequest),
          listener: (context, state) {
            final request = (state as ActiveThreadLoaded).scrollRequest!;
            // Wait for the list to rebuild with the window the cubit loaded,
            // otherwise the target row would not exist yet.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _performScroll(request);
            });
          },
        ),
        BlocListener<ActiveThreadCubit, ActiveThreadState>(
          listenWhen: (prev, next) =>
              prev is ActiveThreadLoaded &&
              next is ActiveThreadLoaded &&
              !identical(prev.messages, next.messages) &&
              prev.scrollRequest == next.scrollRequest,
          listener: (context, state) => _keepAnchor(),
        ),
      ],
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: Column(
          children: [
            Expanded(
              child: ChatWallpaper(
                child: Column(
                  children: [
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned.fill(child: _buildMessageList()),
                          Positioned(
                            top: AppSpacing.sm,
                            bottom: AppSpacing.sm,
                            right: 0,
                            width: 200,
                            child: ChatScrollbar(
                              position: _historyPosition,
                              visible: _scrollbarVisible,
                              dateAt: context
                                  .read<ActiveThreadCubit>()
                                  .dateAtFraction,
                              onJump: context
                                  .read<ActiveThreadCubit>()
                                  .jumpToFraction,
                            ),
                          ),
                          _buildLoadingNewer(),
                          _buildJumpToLatest(),
                        ],
                      ),
                    ),
                    _buildTypingBanner(),
                  ],
                ),
              ),
            ),
            _buildOfflineBanner(),
            _buildComposerSurface(context),
            _buildEmojiPicker(),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineBanner() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      buildWhen: (previous, current) =>
          previous is ActiveThreadLoaded &&
          current is ActiveThreadLoaded &&
          previous.isOffline != current.isOffline,
      builder: (context, state) {
        final isOffline = state is ActiveThreadLoaded ? state.isOffline : false;
        return AnimatedSize(
          duration: AppDuration.normal,
          curve: Curves.easeOut,
          child: isOffline
              ? Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'You are offline. Messages will send when connected.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _stopSearch,
        ),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search this chat',
            border: InputBorder.none,
          ),
          onChanged: (v) => context.read<ActiveThreadCubit>().setSearchQuery(v),
        ),
        actions: [
          BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
            buildWhen: (prev, next) =>
                prev is! ActiveThreadLoaded ||
                next is! ActiveThreadLoaded ||
                prev.searchMatchIds != next.searchMatchIds ||
                prev.currentMatchId != next.currentMatchId ||
                prev.searchInProgress != next.searchInProgress ||
                prev.indexingProgress != next.indexingProgress ||
                prev.searchQuery != next.searchQuery,
            builder: (context, state) {
              if (state is! ActiveThreadLoaded || !state.isSearching) {
                return const SizedBox.shrink();
              }
              final cubit = context.read<ActiveThreadCubit>();
              final total = state.searchMatchIds.length;
              final index = state.currentMatchIndex;
              final String label;
              if (state.searchInProgress && index < 0) {
                label = '…';
              } else if (total == 0) {
                label = 'No results';
              } else {
                label = '${index + 1} of $total';
              }
              final indexing = state.indexingProgress;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (indexing != null) ...[
                    Tooltip(
                      message: 'Indexing older messages…',
                      child: SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: indexing,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  IconButton(
                    tooltip: 'Older match',
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                    onPressed: index >= 0 && index < total - 1
                        ? cubit.nextMatch
                        : null,
                  ),
                  IconButton(
                    tooltip: 'Newer match',
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    onPressed: index > 0 ? cubit.previousMatch : null,
                  ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              _searchCtrl.clear();
              context.read<ActiveThreadCubit>().clearSearch();
            },
          ),
        ],
      );
    }
    return AppBar(
      leadingWidth: 40,
      actions: [
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'search') {
              setState(() => _searching = true);
            } else if (value == 'date') {
              _pickJumpDate();
            } else if (value == 'clear') {
              _confirmClearMessages(context);
            } else if (value == 'delete') {
              _confirmDeleteThread(context);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'search', child: Text('Search this chat')),
            PopupMenuItem(value: 'date', child: Text('Jump to date')),
            PopupMenuItem(value: 'clear', child: Text('Clear messages')),
            PopupMenuItem(value: 'delete', child: Text('Delete thread')),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.lock_outline_rounded),
          tooltip: 'Lock vault',
          onPressed: widget.onLock,
        ),
      ],
      title: BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
        builder: (context, state) {
          final online = state is ActiveThreadLoaded
              ? state.otherIsOnline
              : false;
          final theme = Theme.of(context);
          final semantic = context.semantic;
          final presence = online ? semantic.online : semantic.offline;
          return Row(
            children: [
              _PresenceAvatar(
                user: widget.otherUser,
                online: online,
                ringColor: presence,
              ),
              const SizedBox(width: AppSpacing.sm + AppSpacing.xxs),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.otherUser.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    AnimatedDefaultTextStyle(
                      duration: AppDuration.normal,
                      style:
                          theme.textTheme.labelSmall?.copyWith(
                            color: presence,
                            fontWeight: FontWeight.w500,
                          ) ??
                          TextStyle(color: presence),
                      child: Text(online ? 'Online' : 'Offline'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _stopSearch() {
    _searchCtrl.clear();
    context.read<ActiveThreadCubit>().clearSearch();
    setState(() => _searching = false);
  }

  void _cancelEdit() {
    if (!_isEditing) return;
    setState(() {
      _editingMessage = null;
      _textCtrl.clear();
      _hasText.value = false;
      _showEmojiPicker = false;
      _inputFocus.unfocus();
    });
  }

  Future<void> _commitEdit() async {
    final msg = _editingMessage;
    if (msg == null || !_isEditing) return;
    final edited = _textCtrl.text.trim();
    if (edited.isEmpty) {
      _cancelEdit();
      return;
    }
    final cubit = context.read<ActiveThreadCubit>();
    await cubit.editMessage(msg, edited);
    if (!mounted) return;
    _cancelEdit();
  }

  Widget _buildMessageList() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      builder: (context, state) {
        if (state is ActiveThreadLoading) {
          return const LoadingView(message: 'Decrypting messages…');
        }
        if (state is ActiveThreadError) {
          return ErrorView(message: state.message);
        }
        if (state is! ActiveThreadLoaded) return const SizedBox.shrink();

        final msgs = state.visibleMessages;
        if (msgs.isEmpty) {
          _items = const [];
          return EmptyView(
            icon: Icons.waving_hand_outlined,
            title: 'No messages yet',
            subtitle:
                'Say hello to ${widget.otherUser.displayName} — everything you '
                'send is end-to-end encrypted.',
          );
        }

        final cubit = context.read<ActiveThreadCubit>();
        final myUid = cubit.myUid;

        final showPagingSpinner = state.hasMore;
        final items = _buildThreadItems(msgs, withDayDividers: true);
        _items = items;
        _renderedDetached = state.isDetached;
        final matchIds = state.searchMatchIds.toSet();

        return ScrollablePositionedList.builder(
          itemScrollController: _itemScrollCtrl,
          itemPositionsListener: _itemPositions,
          reverse: true,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.sm,
          ),
          itemCount: items.length + (showPagingSpinner ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == items.length) {
              return const Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }

            final item = items[i];
            if (item.divider != null) {
              return ChatDayDivider(date: item.divider!);
            }

            final msg = item.message!;
            final isMine = msg.senderId == myUid;
            return MessageBubble(
              key: ValueKey(msg.messageId),
              message: msg,
              isMine: isMine,
              myUid: myUid,
              otherUid: widget.otherUser.uid,
              otherIsOnline: state.otherIsOnline,
              mediaLoader: widget.mediaLoader,
              sendStatus: state.uploadProgress[msg.messageId],
              isHighlighted:
                  _highlightedId == msg.messageId ||
                  state.currentMatchId == msg.messageId,
              highlightQuery: matchIds.contains(msg.messageId)
                  ? state.searchQuery
                  : '',
              isFirstInGroup: item.isFirstInGroup,
              isLastInGroup: item.isLastInGroup,
              onReply: () {
                cubit.setReplyTarget(msg);
                _inputFocus.requestFocus();
              },
              onReact: (emoji) => cubit.toggleReaction(msg, emoji),
              // Always wired up for own, non-media messages — eligibility
              // (30-minute / edited-before-read rule) is checked once,
              // centrally, inside `_promptEdit`, so both the long-press menu
              // entry and the Signal-style double-tap give the same
              // accept/reject behaviour instead of silently disappearing.
              onEdit: isMine && !msg.isMedia ? () => _promptEdit(msg) : null,
              onCopy: msg.localDecryptedText?.trim().isNotEmpty == true
                  ? () => _copyMessage(msg.localDecryptedText!)
                  : null,
              canReplyFromLeftToRight: true,
              onTapQuote: _jumpToMessage,
              onSaveToVault: msg.isMedia && !msg.isDocument
                  ? () => _saveToVault(msg)
                  : null,
              onForward: () => _promptForward(msg),
              onRetry: msg.status == MessageStatus.failed
                  ? () => cubit.retryMessage(msg.messageId)
                  : null,
              onDiscard: msg.status == MessageStatus.failed
                  ? () => cubit.discardMessage(msg.messageId)
                  : null,
              onDeleteForMe: () => _confirmDeleteForMe(msg),
              onDeleteForEveryone: isMine
                  ? () => _confirmDeleteForEveryone(msg)
                  : null,
            );
          },
        );
      },
    );
  }

  /// Longest gap between two messages from the same sender that still reads as
  /// one continuous run.
  static const _groupWindow = Duration(minutes: 5);

  /// Flatten [msgs] into renderable rows, newest first to match `reverse: true`.
  ///
  /// Because the list is reversed, `index + 1` is the *older* neighbour and
  /// `index - 1` is the *newer* one — grouping and day dividers both read in
  /// that direction.
  List<_ThreadItem> _buildThreadItems(
    List<ChatMessage> msgs, {
    required bool withDayDividers,
  }) {
    final items = <_ThreadItem>[];

    for (var i = 0; i < msgs.length; i++) {
      final msg = msgs[i];
      final older = i + 1 < msgs.length ? msgs[i + 1] : null;
      final newer = i > 0 ? msgs[i - 1] : null;

      final startsDay = older == null || !_sameDay(older.sentAt, msg.sentAt);

      items.add(
        _ThreadItem.message(
          msg,
          // A day divider always breaks a run.
          isFirstInGroup: startsDay || !_sameRun(older, msg),
          isLastInGroup: !_sameRun(msg, newer),
        ),
      );

      // Appended *after* the message so the reversed list draws it above.
      if (withDayDividers && startsDay) {
        items.add(_ThreadItem.divider(msg.sentAt));
      }
    }

    return items;
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Whether [earlier] and [later] belong to the same visual run.
  static bool _sameRun(ChatMessage? earlier, ChatMessage? later) {
    if (earlier == null || later == null) return false;
    if (earlier.senderId != later.senderId) return false;
    if (!_sameDay(earlier.sentAt, later.sentAt)) return false;
    return later.sentAt.difference(earlier.sentAt).abs() <= _groupWindow;
  }

  /// Scroll to a quoted message and flash it, loading it (with its
  /// surrounding conversation) from local history if it is not on screen.
  Future<void> _jumpToMessage(String messageId) async {
    final found = await context.read<ActiveThreadCubit>().jumpToMessage(
      messageId,
    );
    if (!mounted) return;
    if (!found) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Original message is not on this device.'),
        ),
      );
      return;
    }
    setState(() => _highlightedId = messageId);
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _highlightedId == messageId) {
        setState(() => _highlightedId = null);
      }
    });
  }

  /// Honour a scroll request from the cubit (search match, quote, date,
  /// scrollbar or jump-to-latest).
  void _performScroll(ChatScrollRequest request) {
    if (!_itemScrollCtrl.isAttached) return;
    final id = request.messageId;
    if (id == null) {
      _itemScrollCtrl.jumpTo(index: 0);
      _showJumpToLatest.value = false;
      return;
    }
    final index = _items.indexWhere((i) => i.message?.messageId == id);
    if (index < 0) return;
    final positions = _itemPositions.itemPositions.value;
    final near = positions.any((p) => (p.index - index).abs() < 30);
    if (near) {
      _itemScrollCtrl.scrollTo(
        index: index,
        alignment: 0.4,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      // Animating across a freshly loaded window would flash every message
      // in between; land on the target directly instead.
      _itemScrollCtrl.jumpTo(index: index, alignment: 0.4);
    }
  }

  /// Keep the message under the viewport still when rows are inserted or
  /// dropped below it (newer paging, trimming, arrivals while scrolled up).
  void _keepAnchor() {
    if (!_itemScrollCtrl.isAttached) return;
    final positions = _itemPositions.itemPositions.value.toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    if (positions.isEmpty) return;
    // Pinned to the latest message: let new messages scroll into view.
    if (positions.first.index == 0 && !_renderedDetached) return;
    ItemPosition? anchor;
    String? anchorId;
    for (final p in positions) {
      if (p.index < _items.length && _items[p.index].message != null) {
        anchor = p;
        anchorId = _items[p.index].message!.messageId;
        break;
      }
    }
    if (anchor == null || anchorId == null) return;
    final oldIndex = anchor.index;
    final leadingEdge = anchor.itemLeadingEdge;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_itemScrollCtrl.isAttached) return;
      final newIndex = _items.indexWhere(
        (i) => i.message?.messageId == anchorId,
      );
      if (newIndex < 0 || newIndex == oldIndex) return;
      _itemScrollCtrl.jumpTo(index: newIndex, alignment: leadingEdge);
    });
  }

  Future<void> _pickJumpDate() async {
    final cubit = context.read<ActiveThreadCubit>();
    final bounds = await cubit.historyBounds();
    if (!mounted) return;
    if (bounds == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages saved on this device yet.')),
      );
      return;
    }
    final first = bounds.$1.toLocal();
    final last = bounds.$2.toLocal();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(first.year, first.month, first.day),
      lastDate: DateTime(last.year, last.month, last.day),
      initialDate: DateTime(last.year, last.month, last.day),
      helpText: 'Jump to date',
    );
    if (picked == null || !mounted) return;
    final found = await cubit.jumpToDate(picked);
    if (!found && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No messages around that date.')),
      );
    }
  }

  /// Spinner shown while a detached window pages newer messages in.
  Widget _buildLoadingNewer() {
    // Always positioned: a non-positioned Stack child would size the Stack.
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
        buildWhen: (prev, next) =>
            prev is! ActiveThreadLoaded ||
            next is! ActiveThreadLoaded ||
            prev.loadingNewer != next.loadingNewer,
        builder: (context, state) {
          final loading = state is ActiveThreadLoaded && state.loadingNewer;
          if (!loading) return const SizedBox.shrink();
          return const LinearProgressIndicator(minHeight: 2);
        },
      ),
    );
  }

  /// WhatsApp-style "scroll to latest" button with a badge for messages
  /// that arrived while viewing older history.
  Widget _buildJumpToLatest() {
    return Positioned(
      right: AppSpacing.md,
      bottom: AppSpacing.md,
      child: BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
        buildWhen: (prev, next) =>
            prev is! ActiveThreadLoaded ||
            next is! ActiveThreadLoaded ||
            prev.isDetached != next.isDetached ||
            prev.newWhileDetached != next.newWhileDetached,
        builder: (context, state) {
          final loaded = state is ActiveThreadLoaded ? state : null;
          return ValueListenableBuilder<bool>(
            valueListenable: _showJumpToLatest,
            builder: (context, show, _) {
              final visible = (loaded?.isDetached ?? false) || show;
              final count = loaded?.newWhileDetached ?? 0;
              return AnimatedScale(
                scale: visible ? 1 : 0,
                duration: AppDuration.normal,
                child: Badge(
                  isLabelVisible: count > 0,
                  label: Text('$count'),
                  child: FloatingActionButton.small(
                    heroTag: null,
                    tooltip: 'Scroll to latest',
                    onPressed: visible
                        ? context.read<ActiveThreadCubit>().jumpToLatest
                        : null,
                    child: const Icon(Icons.keyboard_double_arrow_down_rounded),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _confirmClearMessages(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear messages'),
        content: const Text(
          'Remove every message from your view of this chat? '
          'The other person will not be affected and can still see them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (_searching) _stopSearch();
    final threadList = this.context.read<ThreadListCubit>();
    final activeThread = this.context.read<ActiveThreadCubit>();
    await threadList.clearThread(widget.thread.threadId);
    if (!mounted) return;
    await activeThread.openThread(
      thread: widget.thread,
      otherUser: widget.otherUser,
    );
  }

  Future<void> _confirmDeleteThread(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete thread'),
        content: const Text(
          'Delete this conversation and all its messages? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final threadList = this.context.read<ThreadListCubit>();
    final navigator = Navigator.of(this.context);
    await threadList.deleteThread(widget.thread.threadId);
    if (!mounted) return;
    navigator.pop();
  }

  Future<void> _promptEdit(ChatMessage msg) async {
    final cubit = context.read<ActiveThreadCubit>();
    final messenger = ScaffoldMessenger.of(context);
    if (!cubit.canEditMessage(msg)) {
      messenger.showSnackBar(
        const SnackBar(content: Text('This message can no longer be edited.')),
      );
      return;
    }
    final text = msg.localDecryptedText ?? '';
    context.read<ActiveThreadCubit>().clearReplyTarget();
    setState(() {
      _editingMessage = msg;
      _textCtrl.text = text;
      _textCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _textCtrl.text.length),
      );
      _showEmojiPicker = false;
      _hasText.value = _textCtrl.text.trim().isNotEmpty;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  /// "Delete for me" only ever needs a lightweight confirmation since it is
  /// non-destructive to the other participant, but it still goes through the
  /// screen's own stable [context] (never a per-row context) for the same
  /// reason `_promptEdit` does — a `showDialog` awaiting a per-row context
  /// can outlive that context if the list rebuilds mid-dialog.
  Future<void> _confirmDeleteForMe(ChatMessage msg) async {
    final cubit = context.read<ActiveThreadCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete message'),
        content: const Text(
          'Remove this message from your copy of the chat? '
          'The other person will still see it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await cubit.deleteMessageForMe(msg);
  }

  /// "Delete for everyone" is destructive and irreversible, so it gets a
  /// distinct, more explicit confirmation (mirroring Signal/WhatsApp), again
  /// routed through the screen's stable [context].
  Future<void> _confirmDeleteForEveryone(ChatMessage msg) async {
    final cubit = context.read<ActiveThreadCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete for everyone'),
        content: const Text(
          'This message will be deleted for everyone in this chat. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete for everyone'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await cubit.deleteMessageForEveryone(msg);
  }

  /// Pick a conversation and re-send the message into it.
  Future<void> _promptForward(ChatMessage message) async {
    final cubit = context.read<ActiveThreadCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final targets = await cubit.loadForwardTargets();
    if (!mounted) return;
    if (targets.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No other conversations to forward to.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<ForwardTarget>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text(
                'Forward to',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            for (final target in targets)
              ListTile(
                leading: CircleAvatar(
                  backgroundImage: target.user.photoUrl != null
                      ? NetworkImage(target.user.photoUrl!)
                      : null,
                  child: target.user.photoUrl == null
                      ? Text(target.user.initials)
                      : null,
                ),
                title: Text(target.user.displayName),
                subtitle: Text(
                  target.user.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => Navigator.pop(sheetContext, target),
              ),
          ],
        ),
      ),
    );
    if (chosen == null) return;

    await cubit.forwardMessage(
      message,
      targetThreadId: chosen.thread.threadId,
      targetRecipientUid: chosen.user.uid,
    );
    messenger.showSnackBar(
      SnackBar(content: Text('Forwarded to ${chosen.user.displayName}.')),
    );
  }

  Widget _buildTypingBanner() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      buildWhen: (prev, next) {
        final prevTyping = prev is ActiveThreadLoaded
            ? prev.otherIsTyping
            : false;
        final nextTyping = next is ActiveThreadLoaded
            ? next.otherIsTyping
            : false;
        return prevTyping != nextTyping;
      },
      builder: (context, state) {
        final typing = state is ActiveThreadLoaded
            ? state.otherIsTyping
            : false;
        return TypingIndicator(visible: typing);
      },
    );
  }

  /// Quote strip shown above the composer while a reply is staged.
  Widget _buildReplyPreview() {
    return BlocBuilder<ActiveThreadCubit, ActiveThreadState>(
      buildWhen: (prev, next) {
        final prevTarget = prev is ActiveThreadLoaded ? prev.replyTarget : null;
        final nextTarget = next is ActiveThreadLoaded ? next.replyTarget : null;
        return prevTarget != nextTarget;
      },
      builder: (context, state) {
        final target = state is ActiveThreadLoaded ? state.replyTarget : null;
        if (target == null) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;
        final textTheme = Theme.of(context).textTheme;
        final myUid = context.read<ActiveThreadCubit>().myUid;
        final preview = target.isMedia
            ? target.mediaPreview
            : (target.localDecryptedText ?? '');

        return Container(
          margin: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.xs,
            AppSpacing.sm,
            0,
          ),
          padding: const EdgeInsets.only(left: AppSpacing.sm),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: AppRadius.all(AppRadius.md),
            border: Border(left: BorderSide(color: cs.primary, width: 3)),
          ),
          child: Row(
            children: [
              Icon(Icons.reply_rounded, size: 18, color: cs.primary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        target.senderId == myUid
                            ? 'Replying to yourself'
                            : 'Replying to ${widget.otherUser.displayName}',
                        style: textTheme.labelSmall?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Cancel reply',
                onPressed: () =>
                    context.read<ActiveThreadCubit>().clearReplyTarget(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditHeader() {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Text(
            'Edit message',
            style: textTheme.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            tooltip: 'Cancel edit',
            onPressed: _cancelEdit,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  /// The composer surface: reply strip + edit header + input bar sharing one
  /// elevated plane.
  Widget _buildComposerSurface(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isEditing) _buildEditHeader(),
          if (!_isEditing) _buildReplyPreview(),
          _buildInputBar(context),
        ],
      ),
    );
  }

  Widget _buildInputBar(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      // The picker supplies its own bottom inset when open.
      bottom: !_showEmojiPicker,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
          AppSpacing.sm,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Emoji, attach and the field share one pill so the composer reads
            // as a single control rather than three loose widgets.
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: AppRadius.all(AppRadius.pill),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _ComposerAction(
                      icon: _showEmojiPicker
                          ? Icons.keyboard_outlined
                          : Icons.emoji_emotions_outlined,
                      tooltip: _showEmojiPicker ? 'Keyboard' : 'Emoji',
                      onPressed: _toggleEmojiPicker,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _textCtrl,
                        focusNode: _inputFocus,
                        maxLines: 5,
                        minLines: 1,
                        textCapitalization: TextCapitalization.sentences,
                        style: Theme.of(context).textTheme.bodyLarge,
                        onTap: () {
                          if (_showEmojiPicker) {
                            setState(() => _showEmojiPicker = false);
                          }
                        },
                        decoration: InputDecoration(
                          hintText: _isEditing ? 'Edit message' : 'Message',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                          hintStyle: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        onChanged: (v) {
                          if (_isEditing) {
                            _hasText.value = v.trim().isNotEmpty;
                            return;
                          }
                          context.read<ActiveThreadCubit>().onTextChanged(v);
                        },
                      ),
                    ),
                    _ComposerAction(
                      icon: Icons.attach_file_rounded,
                      tooltip: 'Attach',
                      onPressed: () => _pickMedia(context),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _SendButton(
              hasText: _hasText,
              onSend: _isEditing ? _commitEdit : _send,
              icon: _isEditing ? Icons.check_rounded : Icons.send_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Message copied')));
  }

  void _send() {
    final text = _textCtrl.text;
    if (text.trim().isEmpty) return;
    _textCtrl.clear();
    context.read<ActiveThreadCubit>().sendText(text);
  }

  void _toggleEmojiPicker() {
    if (_showEmojiPicker) {
      setState(() => _showEmojiPicker = false);
      _inputFocus.requestFocus();
      return;
    }
    // Drop the keyboard first, otherwise both compete for the same space.
    _inputFocus.unfocus();
    setState(() => _showEmojiPicker = true);
  }

  Widget _buildEmojiPicker() {
    if (!_showEmojiPicker) return const SizedBox.shrink();
    return SizedBox(
      height: 280,
      child: EmojiPicker(
        textEditingController: _textCtrl,
        onEmojiSelected: (category, emoji) {
          // The controller is updated by the picker itself; this only keeps
          // the typing indicator in sync.
          context.read<ActiveThreadCubit>().onTextChanged(_textCtrl.text);
        },
        config: const Config(
          height: 280,
          checkPlatformCompatibility: true,
          emojiViewConfig: EmojiViewConfig(columns: 8, emojiSizeMax: 28),
          categoryViewConfig: CategoryViewConfig(),
          bottomActionBarConfig: BottomActionBarConfig(enabled: false),
        ),
      ),
    );
  }

  Future<void> _pickMedia(BuildContext context) async {
    // Capture before any await to satisfy use_build_context_synchronously.
    final cubit = context.read<ActiveThreadCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photos from gallery'),
              onTap: () => Navigator.pop(sheetContext, 'photo'),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.pop(sheetContext, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Send from vault'),
              onTap: () => Navigator.pop(sheetContext, 'vault'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Video from gallery'),
              onTap: () => Navigator.pop(sheetContext, 'video'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Document'),
              onTap: () => Navigator.pop(sheetContext, 'document'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'vault') {
      await _sendFromVault(cubit);
      return;
    }
    if (choice == 'document') {
      await _sendDocument(cubit);
      return;
    }

    // Gallery photos are multi-select; the camera and video pickers are not.
    if (choice == 'photo') {
      final files = await _picker.pickMultiImage();
      if (files.isEmpty || !mounted) return;
      await _sendImages(cubit, files, messenger);
      return;
    }

    XFile? file;
    MessageType? type;

    if (choice == 'camera') {
      file = await _picker.pickImage(source: ImageSource.camera);
      type = MessageType.image;
    } else if (choice == 'video') {
      file = await _picker.pickVideo(source: ImageSource.gallery);
      type = MessageType.video;
    }

    if (file == null || type == null || !mounted) return;

    if (type == MessageType.image) {
      await _sendImages(cubit, [file], messenger);
      return;
    }

    final length = await file.length();
    if (!mounted) return;
    // Videos are sent as-is, so the limit still applies up front. Photos are
    // checked after compression instead, which can bring a large one under it.
    if (length > ActiveThreadCubit.maxAttachmentBytes) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Attachments must be smaller than 64 MB.')),
      );
      return;
    }
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    await cubit.sendMedia(messageId: _uuid.v4(), rawBytes: bytes, type: type);
  }

  /// Most photos anyone sends at once; beyond this the batch is trimmed rather
  /// than queueing an unbounded amount of compression work.
  static const _maxPhotosPerSend = 10;

  /// Asks for a quality once, then sends every picked photo.
  ///
  /// Photos go out one at a time: each is decoded and re-encoded in full, so
  /// running a whole selection in parallel would multiply peak memory by the
  /// number of photos for no gain on a single connection.
  Future<void> _sendImages(
    ActiveThreadCubit cubit,
    List<XFile> files,
    ScaffoldMessengerState messenger,
  ) async {
    var picked = files;
    if (picked.length > _maxPhotosPerSend) {
      picked = picked.sublist(0, _maxPhotosPerSend);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Sending the first $_maxPhotosPerSend photos.'),
        ),
      );
    }

    // The sheet is sized from the first photo and applies to the whole batch,
    // so picking ten photos is still one decision.
    final firstBytes = await picked.first.readAsBytes();
    if (!mounted) return;
    final quality = await _askImageQuality(firstBytes.length);
    if (quality == null || !mounted) return;

    for (var i = 0; i < picked.length; i++) {
      if (!mounted) return;
      final bytes = i == 0 ? firstBytes : await picked[i].readAsBytes();
      if (!mounted) return;
      // Each photo is its own message, so one failure leaves the rest alone.
      await cubit.sendMedia(
        messageId: _uuid.v4(),
        rawBytes: bytes,
        type: MessageType.image,
        quality: quality,
      );
    }
  }

  /// Shows the quality sheet, seeded with the last choice and remembering a
  /// new one. Returns null if the sheet was dismissed.
  Future<ImageQuality?> _askImageQuality(int originalBytes) async {
    final settings = widget.settingsRepository;
    final remembered = ImageQualityX.parse(
      await settings?.getChatImageQuality(),
    );
    if (!mounted) return null;
    final chosen = await ImageQualitySheet.show(
      context,
      originalBytes: originalBytes,
      selected: remembered,
    );
    if (chosen == null) return null;
    if (chosen != remembered) {
      await settings?.setChatImageQuality(chosen.name);
    }
    return chosen;
  }

  /// Asks which quality to send a single photo at, then sends it.
  Future<void> _sendImageWithQuality(
    ActiveThreadCubit cubit,
    Uint8List bytes,
  ) async {
    final quality = await _askImageQuality(bytes.length);
    if (quality == null || !mounted) return;
    await cubit.sendMedia(
      messageId: _uuid.v4(),
      rawBytes: bytes,
      type: MessageType.image,
      quality: quality,
    );
  }

  /// Attach any file (PDF, Office document, archive…) as an encrypted blob.
  Future<void> _sendDocument(ActiveThreadCubit cubit) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await FilePicker.pickFile();
      if (picked == null || !mounted) return;
      final length = await picked.length();
      if (length != null && length > ActiveThreadCubit.maxAttachmentBytes) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Attachments must be smaller than 64 MB.'),
          ),
        );
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      await cubit.sendMedia(
        messageId: _uuid.v4(),
        rawBytes: bytes,
        type: MessageType.file,
        filename: picked.name,
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not attach file: $e')),
      );
    }
  }

  /// Attach a photo that already lives in the encrypted vault.
  ///
  /// The vault and the chat use different keys, so the photo is decrypted with
  /// the vault key and re-encrypted with the thread key. It is never written to
  /// disk in the clear along the way.
  Future<void> _sendFromVault(ActiveThreadCubit cubit) async {
    final photo = await VaultPickerSheet.show(
      context,
      bridge: widget.vaultBridge,
    );
    if (photo == null || !mounted) return;
    try {
      final bytes = await widget.vaultBridge.readVaultPhoto(photo);
      if (!mounted) return;
      await _sendImageWithQuality(cubit, bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not read vault photo: $e')));
    }
  }

  /// Copy received media into the vault.
  Future<void> _saveToVault(ChatMessage message) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final bytes = await widget.mediaLoader.load(
        threadId: message.threadId,
        storagePath: message.mediaRef!,
      );
      final extension = message.mediaType == MessageType.video ? 'mp4' : 'jpg';
      await widget.vaultBridge.saveToVault(
        bytes: bytes,
        filename: '${message.messageId}.$extension',
      );
      messenger.showSnackBar(const SnackBar(content: Text('Saved to vault.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save to vault: $e')),
      );
    }
  }
}

/// One renderable row in the thread list: either a message or a day divider.
class _ThreadItem {
  const _ThreadItem.message(
    ChatMessage this.message, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : divider = null;

  const _ThreadItem.divider(DateTime this.divider)
    : message = null,
      isFirstInGroup = false,
      isLastInGroup = false;

  final ChatMessage? message;
  final DateTime? divider;
  final bool isFirstInGroup;
  final bool isLastInGroup;
}

/// App-bar avatar with a presence ring, so status reads at a glance.
class _PresenceAvatar extends StatelessWidget {
  const _PresenceAvatar({
    required this.user,
    required this.online,
    required this.ringColor,
  });

  final ChatUser user;
  final bool online;
  final Color ringColor;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: AppDuration.normal,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: online ? ringColor : Colors.transparent,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              backgroundImage: user.photoUrl != null
                  ? NetworkImage(user.photoUrl!)
                  : null,
              child: user.photoUrl == null
                  ? Text(
                      user.initials,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact icon button sized to sit inside the composer pill.
class _ComposerAction extends StatelessWidget {
  const _ComposerAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 22),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      onPressed: onPressed,
    );
  }
}

/// Send/update button that grows into view only once there is something to
/// send or update.
class _SendButton extends StatelessWidget {
  const _SendButton({
    required this.hasText,
    required this.onSend,
    this.icon = Icons.send_rounded,
  });

  final ValueListenable<bool> hasText;
  final VoidCallback onSend;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: hasText,
      builder: (context, enabled, child) {
        return AnimatedScale(
          duration: AppDuration.fast,
          curve: Curves.easeOutBack,
          scale: enabled ? 1 : 0.85,
          child: AnimatedOpacity(
            duration: AppDuration.fast,
            opacity: enabled ? 1 : 0.45,
            child: Material(
              color: enabled ? cs.primary : cs.surfaceContainerHighest,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: enabled ? onSend : null,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Icon(
                    icon,
                    size: 20,
                    color: enabled ? cs.onPrimary : cs.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
