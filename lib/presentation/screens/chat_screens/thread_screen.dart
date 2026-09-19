import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../application/services/chat_notification_service.dart';
import '../../../application/services/chat_vault_bridge.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/message_metadata.dart';
import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../state/chat/active_thread_cubit.dart';
import '../../state/chat/thread_list_cubit.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/chat/chat_day_divider.dart';
import '../../widgets/chat/chat_media_preview.dart';
import '../../widgets/chat/chat_wallpaper.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/typing_indicator.dart';
import '../../widgets/chat/vault_picker_sheet.dart';

/// Push the thread screen, carrying the chat providers across the navigator.
///
/// Routes are pushed onto the root navigator, which sits *above* the chat
/// providers, so the cubit and media loader have to be re-provided explicitly
/// rather than inherited from [context].
Future<void> openThreadScreen(
  BuildContext context, {
  required ChatThread thread,
  required ChatUser otherUser,
  bool replace = false,
}) {
  final activeThread = context.read<ActiveThreadCubit>();
  final mediaLoader = context.read<ChatMediaLoader>();
  final vaultBridge = context.read<ChatVaultBridge>();
  final notifications = context.read<ChatNotificationService>();
  final route = MaterialPageRoute<void>(
    builder: (_) => BlocProvider.value(
      value: activeThread,
      child: ThreadScreen(
        thread: thread,
        otherUser: otherUser,
        mediaLoader: mediaLoader,
        vaultBridge: vaultBridge,
        notificationService: notifications,
      ),
    ),
  );
  final navigator = Navigator.of(context);
  return replace ? navigator.pushReplacement(route) : navigator.push(route);
}

/// The 1:1 chat thread screen.
class ThreadScreen extends StatefulWidget {
  const ThreadScreen({
    super.key,
    required this.thread,
    required this.otherUser,
    required this.mediaLoader,
    required this.vaultBridge,
    this.notificationService,
  });

  final ChatThread thread;
  final ChatUser otherUser;

  /// Passed explicitly rather than read from context: this screen is pushed
  /// onto the root navigator, so it sits outside the chat providers.
  final ChatMediaLoader mediaLoader;

  /// Bridge to the photo vault, for attaching and saving media.
  final ChatVaultBridge vaultBridge;

  /// Told which thread is on screen so it does not notify about it.
  final ChatNotificationService? notificationService;

  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();
  final _uuid = const Uuid();
  final _inputFocus = FocusNode();

  bool _showEmojiPicker = false;
  bool _searching = false;
  final _searchCtrl = TextEditingController();

  /// Message flashed after jumping to it from a quote.
  String? _highlightedId;

  /// Drives the send button's reveal without rebuilding the whole composer on
  /// every keystroke.
  final _hasText = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _textCtrl.addListener(_onTextControllerChanged);
    context.read<ActiveThreadCubit>().openThread(
      thread: widget.thread,
      otherUser: widget.otherUser,
    );
    _scrollCtrl.addListener(_onScroll);
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
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      context.read<ActiveThreadCubit>().loadOlderMessages();
    }
    // Scrolling reveals older messages, which are now read too.
    context.read<ActiveThreadCubit>().markVisibleAsRead();
  }

  @override
  void dispose() {
    widget.notificationService?.setActiveThread(null);
    _textCtrl.removeListener(_onTextControllerChanged);
    _hasText.dispose();
    _textCtrl.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ActiveThreadCubit, ActiveThreadState>(
      listenWhen: (prev, next) {
        final prevErr = prev is ActiveThreadLoaded ? prev.actionError : null;
        final nextErr = next is ActiveThreadLoaded ? next.actionError : null;
        return nextErr != null && nextErr != prevErr;
      },
      listener: (context, state) {
        final message = (state as ActiveThreadLoaded).actionError!;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(message)));
        context.read<ActiveThreadCubit>().clearActionError();
      },
      child: Scaffold(
        appBar: _buildAppBar(context),
        body: Column(
          children: [
            Expanded(
              child: ChatWallpaper(
                child: Column(
                  children: [
                    Expanded(child: _buildMessageList()),
                    _buildTypingBanner(),
                  ],
                ),
              ),
            ),
            _buildComposerSurface(context),
            _buildEmojiPicker(),
          ],
        ),
      ),
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
          onChanged: (v) =>
              context.read<ActiveThreadCubit>().setSearchQuery(v),
        ),
        actions: [
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
            if (value == 'clear') {
              _confirmClearMessages(context);
            } else if (value == 'delete') {
              _confirmDeleteThread(context);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'clear', child: Text('Clear messages')),
            PopupMenuItem(value: 'delete', child: Text('Delete thread')),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = true),
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
          return EmptyView(
            icon: state.searchQuery.isEmpty
                ? Icons.waving_hand_outlined
                : Icons.search_off_outlined,
            title: state.searchQuery.isEmpty
                ? 'No messages yet'
                : 'No matches',
            subtitle: state.searchQuery.isEmpty
                ? 'Say hello to ${widget.otherUser.displayName} — everything you '
                      'send is end-to-end encrypted.'
                : 'Nothing in this chat matches "${state.searchQuery}".',
          );
        }

        final cubit = context.read<ActiveThreadCubit>();
        final myUid = cubit.myUid;

        // Paging while filtered would append messages the filter hides, so the
        // spinner is only offered on the unfiltered list.
        final showPagingSpinner = state.hasMore && state.searchQuery.isEmpty;

        // Day dividers are only meaningful on the unfiltered timeline.
        final items = _buildThreadItems(
          msgs,
          withDayDividers: state.searchQuery.isEmpty,
        );

        return ListView.builder(
          controller: _scrollCtrl,
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
              isHighlighted: _highlightedId == msg.messageId,
              isFirstInGroup: item.isFirstInGroup,
              isLastInGroup: item.isLastInGroup,
              onReply: () {
                cubit.setReplyTarget(msg);
                _inputFocus.requestFocus();
              },
              onReact: (emoji) => cubit.toggleReaction(msg, emoji),
              onEdit: cubit.canEditMessage(msg) ? () => _promptEdit(context, msg) : null,
              onCopy: msg.localDecryptedText?.trim().isNotEmpty == true
                  ? () => _copyMessage(msg.localDecryptedText!)
                  : null,
              canReplyFromLeftToRight: true,
              onTapQuote: _jumpToMessage,
              onSaveToVault: msg.isMedia ? () => _saveToVault(msg) : null,
              onForward: () => _promptForward(msg),
              onRetry: msg.status == MessageStatus.failed
                  ? () => cubit.retryMessage(msg.messageId)
                  : null,
              onDiscard: msg.status == MessageStatus.failed
                  ? () => cubit.discardMessage(msg.messageId)
                  : null,
              onDeleteForMe: () => cubit.deleteMessageForMe(msg),
              onDeleteForEveryone: isMine
                  ? () => cubit.deleteMessageForEveryone(msg)
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

  /// Scroll to a quoted message and flash it.
  ///
  /// Only messages already paged in can be reached; the alternative would be
  /// paging backwards an unbounded number of times to find an old quote.
  void _jumpToMessage(String messageId) {
    final state = context.read<ActiveThreadCubit>().state;
    if (state is! ActiveThreadLoaded) return;
    final index = state.visibleMessages.indexWhere(
      (m) => m.messageId == messageId,
    );
    if (index < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Original message not loaded yet.')),
      );
      return;
    }

    // The list is reversed, so the index maps directly to distance from the
    // bottom. An estimated extent is good enough to nudge it into view.
    _scrollCtrl.animateTo(
      (index * 72.0).clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
    setState(() => _highlightedId = messageId);
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted && _highlightedId == messageId) {
        setState(() => _highlightedId = null);
      }
    });
  }


  Future<void> _confirmClearMessages(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear messages'),
        content: const Text(
          'Delete every message in this chat but keep the conversation?',
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
  Future<void> _promptEdit(BuildContext context, ChatMessage msg) async {
    if (!context.read<ActiveThreadCubit>().canEditMessage(msg)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This message can no longer be edited.')),
      );
      return;
    }
    final cubit = context.read<ActiveThreadCubit>();
    final controller = TextEditingController(
      text: msg.localDecryptedText ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final edited = result?.trim();
    controller.dispose();
    if (!mounted || edited == null || edited.isEmpty) return;
    await cubit.editMessage(msg, edited);
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
            ? (target.mediaType == MessageType.video ? '🎥 Video' : '📷 Photo')
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

  /// The composer surface: reply strip + input bar sharing one elevated plane.
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
        children: [_buildReplyPreview(), _buildInputBar(context)],
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
                          hintText: 'Message',
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
                        onChanged: (v) =>
                            context.read<ActiveThreadCubit>().onTextChanged(v),
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
            _SendButton(hasText: _hasText, onSend: _send),
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
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Photo from gallery'),
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
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    if (choice == 'vault') {
      await _sendFromVault(cubit);
      return;
    }

    XFile? file;
    MessageType? type;

    if (choice == 'photo') {
      file = await _picker.pickImage(source: ImageSource.gallery);
      type = MessageType.image;
    } else if (choice == 'camera') {
      file = await _picker.pickImage(source: ImageSource.camera);
      type = MessageType.image;
    } else if (choice == 'video') {
      file = await _picker.pickVideo(source: ImageSource.gallery);
      type = MessageType.video;
    }

    if (file == null || type == null || !mounted) return;

    final bytes = await file.readAsBytes();
    final msgId = _uuid.v4();
    if (!mounted) return;
    await cubit.sendMedia(messageId: msgId, rawBytes: bytes, type: type);
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
      await cubit.sendMedia(
        messageId: _uuid.v4(),
        rawBytes: bytes,
        type: MessageType.image,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not read vault photo: $e')),
      );
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
      messenger.showSnackBar(
        const SnackBar(content: Text('Saved to vault.')),
      );
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

/// Send button that grows into view only once there is something to send.
class _SendButton extends StatelessWidget {
  const _SendButton({required this.hasText, required this.onSend});

  final ValueListenable<bool> hasText;
  final VoidCallback onSend;

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
                    Icons.send_rounded,
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
