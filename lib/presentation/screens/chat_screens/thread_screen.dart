import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../application/services/chat_notification_service.dart';
import '../../../application/services/chat_vault_bridge.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/message_metadata.dart';
import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../state/chat/active_thread_cubit.dart';
import '../../widgets/chat/chat_media_preview.dart';
import '../../widgets/chat/message_bubble.dart';
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

  @override
  void initState() {
    super.initState();
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
            Expanded(child: _buildMessageList()),
            _buildTypingBanner(),
            _buildReplyPreview(),
            _buildInputBar(context),
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
          return Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundImage: widget.otherUser.photoUrl != null
                    ? NetworkImage(widget.otherUser.photoUrl!)
                    : null,
                child: widget.otherUser.photoUrl == null
                    ? Text(widget.otherUser.initials)
                    : null,
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.otherUser.displayName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    online ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      color: online ? Colors.green : Colors.grey,
                    ),
                  ),
                ],
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
          return const Center(child: CircularProgressIndicator());
        }
        if (state is ActiveThreadError) {
          return Center(child: Text(state.message));
        }
        if (state is! ActiveThreadLoaded) return const SizedBox.shrink();

        final msgs = state.visibleMessages;
        if (msgs.isEmpty) {
          return Center(
            child: Text(
              state.searchQuery.isEmpty
                  ? 'No messages yet. Say hello! 👋'
                  : 'No messages match "${state.searchQuery}".',
            ),
          );
        }

        final cubit = context.read<ActiveThreadCubit>();
        final myUid = cubit.myUid;

        // Paging while filtered would append messages the filter hides, so the
        // spinner is only offered on the unfiltered list.
        final showPagingSpinner = state.hasMore && state.searchQuery.isEmpty;

        return ListView.builder(
          controller: _scrollCtrl,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          itemCount: msgs.length + (showPagingSpinner ? 1 : 0),
          itemBuilder: (context, i) {
            if (i == msgs.length) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              );
            }
            final msg = msgs[i];
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
              onReply: () {
                cubit.setReplyTarget(msg);
                _inputFocus.requestFocus();
              },
              onReact: (emoji) => cubit.toggleReaction(msg, emoji),
              onEdit: isMine ? () => _promptEdit(context, msg) : null,
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

  Future<void> _promptEdit(BuildContext context, ChatMessage msg) async {
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
    controller.dispose();
    if (result == null) return;
    await cubit.editMessage(msg, result);
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
        if (!typing) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${widget.otherUser.displayName} is typing...',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        );
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
        final myUid = context.read<ActiveThreadCubit>().myUid;
        final preview = target.isMedia
            ? (target.mediaType == MessageType.video ? '🎥 Video' : '📷 Photo')
            : (target.localDecryptedText ?? '');

        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
            border: Border(left: BorderSide(color: cs.primary, width: 3)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      target.senderId == myUid
                          ? 'Replying to yourself'
                          : 'Replying to ${widget.otherUser.displayName}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.primary,
                      ),
                    ),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () =>
                    context.read<ActiveThreadCubit>().clearReplyTarget(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar(BuildContext context) {
    return SafeArea(
      top: false,
      // The picker supplies its own bottom inset when open.
      bottom: !_showEmojiPicker,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: Icon(
                _showEmojiPicker
                    ? Icons.keyboard_outlined
                    : Icons.emoji_emotions_outlined,
              ),
              onPressed: _toggleEmojiPicker,
            ),
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: () => _pickMedia(context),
            ),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                focusNode: _inputFocus,
                maxLines: 5,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                onTap: () {
                  if (_showEmojiPicker) {
                    setState(() => _showEmojiPicker = false);
                  }
                },
                decoration: InputDecoration(
                  hintText: 'Message',
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onChanged: (v) =>
                    context.read<ActiveThreadCubit>().onTextChanged(v),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              heroTag: 'send_btn',
              onPressed: _send,
              child: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
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
