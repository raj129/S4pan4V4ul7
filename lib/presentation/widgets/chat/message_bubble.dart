import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/message_metadata.dart';
import '../../../domain/entities/message_reply.dart';
import '../../../domain/search/chat_search_tokenizer.dart';
import '../../screens/chat_screens/chat_image_viewer_screen.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/chat_theme.dart';
import 'animated_emoji.dart';
import 'chat_bubble_shape.dart';
import 'chat_media_preview.dart';
import '../../state/chat/media_send_status.dart';

/// Emoji offered in the quick reaction bar, matching WhatsApp's default set.
const kQuickReactions = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

/// A single chat message.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.myUid,
    required this.otherUid,
    required this.mediaLoader,
    required this.onDeleteForMe,
    this.otherIsOnline = false,
    this.isFirstInGroup = true,
    this.isLastInGroup = true,
    this.onDeleteForEveryone,
    this.onReply,
    this.onReact,
    this.onEdit,
    this.onSaveToVault,
    this.onForward,
    this.onTapQuote,
    this.onRetry,
    this.onDiscard,
    this.onCopy,
    this.canReplyFromLeftToRight = true,
    this.isHighlighted = false,
    this.highlightQuery = '',

    this.sendStatus,
  });

  final ChatMessage message;
  final bool isMine;
  final String myUid;
  final String otherUid;
  final bool otherIsOnline;

  /// First message of a consecutive run by the same sender: draws the tail.
  final bool isFirstInGroup;

  /// Last message of a run: carries the larger gap to the next group.
  final bool isLastInGroup;

  final ChatMediaLoader mediaLoader;
  final VoidCallback onDeleteForMe;
  final VoidCallback? onDeleteForEveryone;
  final VoidCallback? onReply;
  final void Function(String emoji)? onReact;
  final VoidCallback? onEdit;

  /// Copy this attachment into the encrypted photo vault.
  final VoidCallback? onSaveToVault;

  /// Re-send this message into another conversation.
  final VoidCallback? onForward;

  /// Jump to the quoted message.
  final void Function(String messageId)? onTapQuote;

  /// Re-attempt delivery of a message still stuck in the outbox.
  final VoidCallback? onRetry;

  /// Drop a failed message from the outbox without sending it.
  final VoidCallback? onDiscard;

  /// Copy the decrypted text to the clipboard.
  final VoidCallback? onCopy;

  /// Force every reply swipe to use the same left-to-right gesture.
  final bool canReplyFromLeftToRight;

  /// Tinted after the user jumps here from a quote, or while this is the
  /// current search match.
  final bool isHighlighted;

  /// Search term whose occurrences are marked inside the message text.
  final String highlightQuery;

  /// Send progress of this attachment, null once it is sent.
  final MediaSendStatus? sendStatus;

  @override
  Widget build(BuildContext context) {
    // "Delete for me" and "delete for everyone" must look identical and be
    // fully non-interactive: isDeletedFor(myUid) covers both cases (it is
    // true when deletedForEveryone is set, or when this user's uid is in
    // deletedFor), so a single check keeps both delete paths in sync.
    if (message.isDeletedFor(myUid)) {
      return _TombstoneBubble(
        messageId: message.messageId,
        isMine: isMine,
        isLastInGroup: isLastInGroup,
        onReply: onReply,
      );
    }

    final cs = Theme.of(context).colorScheme;
    final chat = context.chatColors;
    final bgColor = chat.bubbleFor(isMine: isMine);
    final textColor = chat.onBubbleFor(isMine: isMine);
    final grouped = message.groupedReactions;

    // Emoji-only messages render bare and oversized, as in WhatsApp.
    final bare = message.isEmojiOnly;

    final shape = ChatBubbleShape(
      isMine: isMine,
      withTail: isFirstInGroup && !bare,
    );

    final bubble = bare
        ? AnimatedContainer(
            duration: AppDuration.normal,
            decoration: BoxDecoration(
              color: isHighlighted
                  ? cs.tertiaryContainer
                  : cs.tertiaryContainer.withValues(alpha: 0),
              borderRadius: AppRadius.all(AppRadius.sm),
            ),
            child: _BubbleContent(
              message: message,
              isMine: isMine,
              myUid: myUid,
              otherUid: otherUid,
              otherIsOnline: otherIsOnline,
              mediaLoader: mediaLoader,
              sendStatus: sendStatus,
              onTapQuote: onTapQuote,
              textColor: cs.onSurface,
              metaColor: cs.onSurfaceVariant,
              bare: true,
              highlightQuery: highlightQuery,
              onLongPress: () => _showActionSheet(context),
            ),
          )
        : Material(
            color: isHighlighted ? cs.tertiaryContainer : bgColor,
            shape: shape,
            elevation: AppElevation.raised,
            shadowColor: chat.bubbleShadow,
            animationDuration: AppDuration.normal,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.md + shape.tailInsets.left,
                AppSpacing.sm,
                AppSpacing.md + shape.tailInsets.right,
                AppSpacing.sm,
              ),
              child: _BubbleContent(
                message: message,
                isMine: isMine,
                myUid: myUid,
                otherUid: otherUid,
                otherIsOnline: otherIsOnline,
                mediaLoader: mediaLoader,
                sendStatus: sendStatus,
                onTapQuote: onTapQuote,
                textColor: isHighlighted ? cs.onTertiaryContainer : textColor,
                metaColor: isHighlighted ? cs.onTertiaryContainer : textColor,
                bare: false,
                highlightQuery: highlightQuery,
                onLongPress: () => _showActionSheet(context),
              ),
            ),
          );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(
          top: AppSpacing.xxs,
          bottom: isLastInGroup ? AppSpacing.sm : AppSpacing.xxs,
          left: isMine ? AppSpacing.xxl : AppSpacing.sm,
          right: isMine ? AppSpacing.sm : AppSpacing.xxl,
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Dismissible(
              key: ValueKey('swipe_${message.messageId}'),
              direction: onReply == null || !canReplyFromLeftToRight
                  ? DismissDirection.none
                  : DismissDirection.startToEnd,
              dismissThresholds: const {DismissDirection.startToEnd: 0.25},
              confirmDismiss: (_) async {
                onReply?.call();
                return false;
              },
              background: const _ReplySwipeBackground(alignEnd: false),
              secondaryBackground: const SizedBox.shrink(),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onLongPress: () => _showActionSheet(context),
                // Signal-style: double-tapping your own message jumps
                // straight to edit. `onEdit` is only wired up for own
                // messages, so this is a no-op on incoming messages. The
                // 30-minute/edited-before-read rule itself is enforced
                // centrally in `ActiveThreadCubit.canEditMessage` /
                // `_promptEdit`, so the double-tap always attempts the
                // action and lets that single source of truth decide
                // whether it succeeds or surfaces a "can no longer be
                // edited" message.
                onDoubleTap: isMine ? onEdit : null,
                child: AnimatedContainer(
                  duration: AppDuration.normal,
                  curve: Curves.easeOut,
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                    minWidth: 0,
                  ),
                  child: bubble,
                ),
              ),
            ),
            if (grouped.isNotEmpty)
              _ReactionRow(grouped: grouped, myUid: myUid, onTap: onReact),
          ],
        ),
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.status == MessageStatus.failed) ...[
              if (onRetry != null)
                ListTile(
                  leading: const Icon(Icons.refresh_rounded),
                  title: const Text('Try again'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onRetry!();
                  },
                ),
              if (onDiscard != null)
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: cs.error),
                  title: Text(
                    'Discard unsent message',
                    style: TextStyle(color: cs.error),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onDiscard!();
                  },
                ),
              const Divider(height: 1),
            ],
            if (onReact != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.sm,
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: AppRadius.all(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final emoji in kQuickReactions)
                        _QuickReactionButton(
                          emoji: emoji,
                          selected: message.reactionOf(myUid) == emoji,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            onReact!(emoji);
                          },
                        ),
                      _MoreReactionsButton(
                        current:
                            kQuickReactions.contains(message.reactionOf(myUid))
                            ? null
                            : message.reactionOf(myUid),
                        onTap: () async {
                          Navigator.pop(sheetContext);
                          final emoji = await showReactionPicker(context);
                          if (emoji != null) onReact!(emoji);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Reply'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onReply!();
                },
              ),
            if (isMine && onEdit != null && !message.isMedia)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onEdit!();
                },
              ),
            if (onCopy != null && !message.isMedia)
              ListTile(
                leading: const Icon(Icons.content_copy_rounded),
                title: const Text('Copy message'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onCopy!();
                },
              ),
            if (onForward != null)
              ListTile(
                leading: const Icon(Icons.shortcut_rounded),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onForward!();
                },
              ),
            if (onSaveToVault != null)
              ListTile(
                leading: const Icon(Icons.lock_outline_rounded),
                title: const Text('Save to vault'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onSaveToVault!();
                },
              ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: cs.error),
              title: Text('Delete for me', style: TextStyle(color: cs.error)),
              onTap: () {
                Navigator.pop(sheetContext);
                onDeleteForMe();
              },
            ),
            if (onDeleteForEveryone != null)
              ListTile(
                leading: Icon(Icons.delete_sweep_outlined, color: cs.error),
                title: Text(
                  'Delete for everyone',
                  style: TextStyle(color: cs.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onDeleteForEveryone!();
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// Inner layout of a bubble: forwarded marker, quote, media, text, meta row.
///
/// Split out so the bare (emoji-only) and framed variants stay in sync.
class _BubbleContent extends StatelessWidget {
  const _BubbleContent({
    required this.message,
    required this.isMine,
    required this.myUid,
    required this.otherUid,
    required this.otherIsOnline,
    required this.mediaLoader,
    required this.onTapQuote,
    required this.textColor,
    required this.metaColor,
    required this.bare,
    required this.onLongPress,
    this.highlightQuery = '',

    this.sendStatus,
  });

  final ChatMessage message;
  final bool isMine;
  final String myUid;
  final String otherUid;
  final bool otherIsOnline;
  final ChatMediaLoader mediaLoader;
  final void Function(String messageId)? onTapQuote;
  final Color textColor;
  final Color metaColor;
  final bool bare;
  final VoidCallback onLongPress;
  final String highlightQuery;

  /// Send progress of this attachment, null once it is sent.
  final MediaSendStatus? sendStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = message.localDecryptedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isForwarded)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.shortcut_rounded,
                  size: 13,
                  color: textColor.withValues(alpha: 0.7),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  'Forwarded',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: textColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        if (message.replyTo != null)
          _QuotedHeader(
            reply: message.replyTo!,
            isMine: isMine,
            myUid: myUid,
            textColor: textColor,
            onTap: onTapQuote == null
                ? null
                : () => onTapQuote!(message.replyTo!.messageId),
          ),
        if (message.isDocument)
          ChatDocumentTile(
            message: message,
            loader: mediaLoader,
            textColor: textColor,
          )
        else if (message.isMedia)
          ClipRRect(
            borderRadius: AppRadius.all(AppRadius.sm),
            child: ChatMediaPreview(
              message: message,
              loader: mediaLoader,
              sendStatus: sendStatus,
              onTap: message.mediaType == MessageType.image
                  ? () => ChatImageViewerScreen.open(
                      context,
                      message: message,
                      loader: mediaLoader,
                    )
                  : null,
            ),
          ),
        // A document's body is its file name, already shown in the tile.
        if (text != null && text.isNotEmpty && !message.isDocument)
          Padding(
            padding: EdgeInsets.only(top: message.isMedia ? AppSpacing.sm : 0),
            child: bare
                ? AnimatedEmojiText(
                    text: text,
                    playbackId: message.messageId,
                    onLongPress: onLongPress,
                  )
                : _MessageText(
                    text: text,
                    color: textColor,
                    bare: false,
                    highlightQuery: highlightQuery,
                  ),
          ),
        const SizedBox(height: AppSpacing.xxs),
        // `Row(mainAxisSize: min)` rather than `Align`: an unconstrained
        // `Align` always expands to the maximum width offered by its parent,
        // which was silently stretching every bubble (even a one-word
        // message) out to the 78%-of-screen cap. A shrink-wrapped Row lets
        // the bubble's width track its actual content again.
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _MetaRow(
              message: message,
              isMine: isMine,
              otherUid: otherUid,
              otherIsOnline: otherIsOnline,
              textColor: metaColor,
            ),
          ],
        ),
      ],
    );
  }
}

class _QuickReactionButton extends StatelessWidget {
  const _QuickReactionButton({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: AnimatedContainer(
        duration: AppDuration.fast,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 26)),
      ),
    );
  }
}

/// Emoji picker themed from the app colour scheme, with a WhatsApp/Gboard-style
/// bottom bar (search + backspace). While the search view is open the picker
/// collapses to [searchHeight] so it hugs the keyboard.
class ThemedEmojiPicker extends StatefulWidget {
  const ThemedEmojiPicker({
    super.key,
    required this.onEmojiSelected,
    this.textEditingController,
    this.height = 280,
    this.searchHeight = 170,
    this.showBackspace = true,
  });

  final OnEmojiSelected onEmojiSelected;
  final TextEditingController? textEditingController;
  final double height;
  final double searchHeight;
  final bool showBackspace;

  @override
  State<ThemedEmojiPicker> createState() => _ThemedEmojiPickerState();
}

class _ThemedEmojiPickerState extends State<ThemedEmojiPicker> {
  final _searching = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _searching.dispose();
    super.dispose();
  }

  Config _config(BuildContext context, double height) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bg = cs.surfaceContainerHigh;
    return Config(
      height: height,
      checkPlatformCompatibility: true,
      emojiViewConfig: EmojiViewConfig(
        columns: 8,
        emojiSizeMax: 28,
        backgroundColor: bg,
      ),
      categoryViewConfig: CategoryViewConfig(
        backgroundColor: bg,
        indicatorColor: cs.primary,
        iconColor: cs.onSurfaceVariant,
        iconColorSelected: cs.primary,
        backspaceColor: cs.primary,
        dividerColor: cs.outlineVariant,
      ),
      bottomActionBarConfig: BottomActionBarConfig(
        backgroundColor: bg,
        buttonColor: Colors.transparent,
        buttonIconColor: cs.onSurfaceVariant,
        showBackspaceButton: widget.showBackspace,
        showSearchViewButton: true,
      ),
      searchViewConfig: SearchViewConfig(
        backgroundColor: bg,
        buttonIconColor: cs.onSurfaceVariant,
        inputTextStyle: theme.textTheme.bodyLarge,
        hintText: 'Search emoji',
        hintTextStyle: theme.textTheme.bodyLarge?.copyWith(
          color: cs.onSurfaceVariant,
        ),
        customSearchView: (config, state, showEmojiView) =>
            _EmojiSearchView(config, state, showEmojiView, _searching),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: _searching,
      builder: (context, searching, _) {
        final h = searching ? widget.searchHeight : widget.height;
        return SizedBox(
          height: h,
          child: EmojiPicker(
            textEditingController: widget.textEditingController,
            onEmojiSelected: widget.onEmojiSelected,
            config: _config(context, h),
          ),
        );
      },
    );
  }
}

/// Search view showing two rows of results; an empty query shows recents.
class _EmojiSearchView extends SearchView {
  const _EmojiSearchView(
    super.config,
    super.state,
    super.showEmojiView,
    this.searching,
  );

  final ValueNotifier<bool> searching;

  @override
  SearchViewState<_EmojiSearchView> createState() => _EmojiSearchViewState();
}

class _EmojiSearchViewState extends SearchViewState<_EmojiSearchView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.searching.value = true;
    });
  }

  @override
  void dispose() {
    final searching = widget.searching;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => searching.value = false,
    );
    super.dispose();
  }

  @override
  void onTextInputChanged(String text) {
    if (text.trim().isNotEmpty) {
      super.onTextInputChanged(text);
      return;
    }
    utils.getRecentEmojis().then((recents) {
      if (!mounted) return;
      setState(() {
        links.clear();
        results
          ..clear()
          ..addAll(recents.map((e) => e.emoji));
        for (final e in results) {
          links[e.emoji] = LayerLink();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final emojiSize = cfg.emojiViewConfig.getEmojiSize(
          constraints.maxWidth,
        );
        final box = cfg.emojiViewConfig.getEmojiBoxSize(constraints.maxWidth);
        return Container(
          color: cfg.searchViewConfig.backgroundColor,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: box * 2 + 4,
                child: results.isEmpty
                    ? Center(
                        child: Text(
                          'No emoji found',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      )
                    : Material(
                        color: Colors.transparent,
                        child: GridView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisExtent: box,
                              ),
                          itemCount: results.length,
                          itemBuilder: (context, i) =>
                              buildEmoji(results[i], emojiSize, box),
                        ),
                      ),
              ),
              SizedBox(
                height: 44,
                child: Row(
                  children: [
                    IconButton(
                      onPressed: widget.showEmojiView,
                      color: cfg.searchViewConfig.buttonIconColor,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    Expanded(
                      child: TextField(
                        onChanged: onTextInputChanged,
                        focusNode: focusNode,
                        style: cfg.searchViewConfig.inputTextStyle,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          hintText: cfg.searchViewConfig.hintText,
                          hintStyle: cfg.searchViewConfig.hintTextStyle,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Opens the full emoji picker and resolves to the chosen emoji, or null if
/// the sheet was dismissed.
Future<String?> showReactionPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (pickerContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(pickerContext).bottom,
      ),
      child: SafeArea(
        child: ThemedEmojiPicker(
          height: 360,
          showBackspace: false,
          onEmojiSelected: (category, emoji) =>
              Navigator.pop(pickerContext, emoji.emoji),
        ),
      ),
    ),
  );
}

/// Last slot of the quick-reaction bar: opens the full picker. When my current
/// reaction is not one of the quick ones it is shown here, highlighted.
class _MoreReactionsButton extends StatelessWidget {
  const _MoreReactionsButton({required this.current, required this.onTap});

  final String? current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final custom = current;
    return Tooltip(
      message: 'More reactions',
      child: InkResponse(
        onTap: onTap,
        radius: 28,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: custom != null
                ? cs.primary.withValues(alpha: 0.18)
                : cs.surfaceContainerHigh,
          ),
          child: custom != null
              ? Text(custom, style: const TextStyle(fontSize: 26))
              : Icon(Icons.add_rounded, size: 28, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Timestamp, edited marker and delivery ticks.
class _MetaRow extends StatelessWidget {
  const _MetaRow({
    required this.message,
    required this.isMine,
    required this.otherUid,
    required this.otherIsOnline,
    required this.textColor,
  });

  final ChatMessage message;
  final bool isMine;
  final String otherUid;
  final bool otherIsOnline;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    final faded = textColor.withValues(alpha: 0.65);
    // Prefer the locally-supplied status (outbox: sending/failed); otherwise
    // derive it from whether the recipient has actually read the message.
    final status =
        message.status ??
        MessageStatusX.forOneToOne(
          readByRecipient: message.isReadBy(otherUid),
          recipientOnline: otherIsOnline,
        );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (message.isEdited)
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Text('edited', style: AppTypography.bubbleMeta(faded)),
          ),
        Text(
          DateFormat.jm().format(message.sentAt.toLocal()),
          style: AppTypography.bubbleMeta(faded),
        ),
        if (isMine) ...[
          if (status == MessageStatus.sending || status == MessageStatus.failed)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.xs),
              child: Text(
                status == MessageStatus.sending ? 'Sending' : 'Not sent',
                style: AppTypography.bubbleMeta(
                  status == MessageStatus.failed
                      ? Theme.of(context).colorScheme.error
                      : faded,
                ),
              ),
            ),
          const SizedBox(width: AppSpacing.xs),
          _StatusTicks(status: status, color: faded),
        ],
      ],
    );
  }
}

/// WhatsApp-style delivery ticks.
class _StatusTicks extends StatelessWidget {
  const _StatusTicks({required this.status, required this.color});

  final MessageStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final (icon, label, iconColor) = switch (status) {
      MessageStatus.sending => (Icons.schedule_rounded, 'Sending', color),
      MessageStatus.failed => (
        Icons.error_outline_rounded,
        'Not sent',
        Theme.of(context).colorScheme.error,
      ),
      MessageStatus.read => (
        Icons.done_all_rounded,
        'Read',
        context.chatColors.readTick,
      ),
      MessageStatus.delivered => (Icons.done_all_rounded, 'Delivered', color),
      MessageStatus.sent => (Icons.done_rounded, 'Sent', color),
    };
    return Semantics(
      label: label,
      child: AnimatedSwitcher(
        duration: AppDuration.fast,
        child: Icon(
          icon,
          key: ValueKey(status),
          size: status == MessageStatus.failed ? 14 : 15,
          color: iconColor,
        ),
      ),
    );
  }
}

/// The quoted preview shown above a reply.
class _QuotedHeader extends StatelessWidget {
  const _QuotedHeader({
    required this.reply,
    required this.isMine,
    required this.myUid,
    required this.textColor,
    this.onTap,
  });

  final MessageReply reply;
  final bool isMine;
  final String myUid;
  final Color textColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isMine ? textColor : context.chatColors.quoteStrip;
    final label = reply.senderId == myUid ? 'You' : 'Them';
    final preview = reply.localDecryptedPreview?.trim();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          AppSpacing.xs + 2,
          AppSpacing.sm,
          AppSpacing.xs + 2,
        ),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: AppRadius.all(AppRadius.xs),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            if (preview != null && preview.isNotEmpty)
              Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor.withValues(alpha: 0.8),
                ),
              )
            else if (reply.mediaType == null)
              Text(
                '🔒 Message',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: textColor.withValues(alpha: 0.8),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Reaction chips shown under a bubble.
class _ReactionRow extends StatelessWidget {
  const _ReactionRow({required this.grouped, required this.myUid, this.onTap});

  final Map<String, List<String>> grouped;
  final String myUid;
  final void Function(String emoji)? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Transform.translate(
      // Overlap the bubble slightly so the chips read as attached to it.
      offset: const Offset(0, -6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final entry in grouped.entries)
              GestureDetector(
                onTap: onTap == null ? null : () => onTap!(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: entry.value.contains(myUid)
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest,
                    borderRadius: AppRadius.all(AppRadius.pill),
                    border: Border.all(color: cs.surface, width: 1.5),
                  ),
                  child: Text(
                    entry.value.length > 1
                        ? '${entry.key} ${entry.value.length}'
                        : entry.key,
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "This message was deleted" placeholder.
///
/// The document is kept rather than removed so the message does not silently
/// vanish from the other side of the conversation.
class _TombstoneBubble extends StatelessWidget {
  const _TombstoneBubble({
    required this.messageId,
    required this.isMine,
    required this.isLastInGroup,
    this.onReply,
  });

  final String messageId;
  final bool isMine;
  final bool isLastInGroup;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final child = Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: EdgeInsets.only(
          top: AppSpacing.xxs,
          bottom: isLastInGroup ? AppSpacing.sm : AppSpacing.xxs,
          left: isMine ? AppSpacing.xxl : AppSpacing.sm,
          right: isMine ? AppSpacing.sm : AppSpacing.xxl,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: AppRadius.all(AppRadius.lg),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, size: 15, color: cs.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Text(
              'This message was deleted',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );

    if (onReply == null) {
      return child;
    }

    return Dismissible(
      key: ValueKey('reply_deleted_$messageId'),
      direction: DismissDirection.startToEnd,
      dismissThresholds: const {DismissDirection.startToEnd: 0.25},
      confirmDismiss: (_) async {
        onReply!.call();
        return false;
      },
      background: const _ReplySwipeBackground(alignEnd: false),
      secondaryBackground: const SizedBox.shrink(),
      child: child,
    );
  }
}

/// Reply icon revealed while swiping a bubble.
class _ReplySwipeBackground extends StatelessWidget {
  const _ReplySwipeBackground({required this.alignEnd});

  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primary.withValues(alpha: 0.15),
          ),
          child: Icon(Icons.reply_rounded, size: 20, color: cs.primary),
        ),
      ),
    );
  }
}

class _MessageText extends StatelessWidget {
  const _MessageText({
    required this.text,
    required this.color,
    required this.bare,
    this.highlightQuery = '',
  });

  final String text;
  final Color color;
  final bool bare;
  final String highlightQuery;

  /// Split `text[from, to)` into plain and highlighted spans.
  static List<InlineSpan> _highlightSpans(
    String text,
    int from,
    int to,
    List<(int, int)> ranges,
    TextStyle highlight,
  ) {
    final spans = <InlineSpan>[];
    var pos = from;
    for (final (rs, re) in ranges) {
      final s = rs < from ? from : rs;
      final e = re > to ? to : re;
      if (e <= s) continue;
      if (s > pos) spans.add(TextSpan(text: text.substring(pos, s)));
      spans.add(TextSpan(text: text.substring(s, e), style: highlight));
      pos = e;
    }
    if (pos < to) spans.add(TextSpan(text: text.substring(pos, to)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final highlight = TextStyle(
      backgroundColor: cs.tertiary.withValues(alpha: 0.35),
      fontWeight: FontWeight.w700,
    );
    // Word-prefix ranges, matching exactly what the search index matched.
    final ranges = highlightQuery.trim().isEmpty
        ? const <(int, int)>[]
        : ChatSearchTokenizer.highlightRanges(text, highlightQuery);
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);
    var start = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.addAll(
          _highlightSpans(text, start, match.start, ranges, highlight),
        );
      }
      final raw = match.group(0)!;
      final linkHit = ranges.any((r) => r.$1 < match.end && r.$2 > match.start);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () =>
                launchUrl(Uri.parse(raw), mode: LaunchMode.externalApplication),
            child: Text(
              raw,
              style:
                  (bare
                          ? const TextStyle(fontSize: 44, height: 1.1)
                          : theme.textTheme.bodyLarge)
                      ?.copyWith(
                        color: color,
                        decoration: TextDecoration.underline,
                        decorationColor: color.withValues(alpha: 0.8),
                        backgroundColor: linkHit
                            ? highlight.backgroundColor
                            : null,
                      ),
            ),
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.addAll(
        _highlightSpans(text, start, text.length, ranges, highlight),
      );
    }

    // Not selectable: a SelectableText would swallow the long-press and start
    // text selection instead of opening the message action sheet (which has
    // "Copy message").
    return Text.rich(
      TextSpan(
        style: bare
            ? const TextStyle(fontSize: 44, height: 1.1)
            : theme.textTheme.bodyLarge?.copyWith(color: color),
        children: spans.isEmpty ? [TextSpan(text: text)] : spans,
      ),
    );
  }
}
