import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/message_metadata.dart';
import '../../../domain/entities/message_reply.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/chat_theme.dart';
import 'chat_bubble_shape.dart';
import 'chat_media_preview.dart';

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

  /// Briefly tinted after the user jumps here from a quote.
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    if (message.deletedForEveryone) {
      return _TombstoneBubble(
        isMine: isMine,
        isLastInGroup: isLastInGroup,
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

    return Align(
      alignment: Alignment.centerRight,
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
              // Swipe toward the centre of the screen to reply, in the
              // direction that feels natural for each side of the conversation.
              direction: onReply == null || !canReplyFromLeftToRight
                  ? DismissDirection.none
                  : DismissDirection.startToEnd,
              dismissThresholds: const {
                DismissDirection.startToEnd: 0.25,
              },
              confirmDismiss: (_) async {
                onReply?.call();
                // Never actually dismiss: the swipe is a shortcut, not a delete.
                return false;
              },
              background: const _ReplySwipeBackground(alignEnd: false),
              secondaryBackground: const SizedBox.shrink(),
              child: GestureDetector(
                onLongPress: () => _showActionSheet(context),
                child: AnimatedContainer(
                  duration: AppDuration.normal,
                  curve: Curves.easeOut,
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.76,
                  ),
                  child: bare
                      ? _BubbleContent(
                          message: message,
                          isMine: isMine,
                          myUid: myUid,
                          otherUid: otherUid,
                          otherIsOnline: otherIsOnline,
                          mediaLoader: mediaLoader,
                          onTapQuote: onTapQuote,
                          textColor: cs.onSurface,
                          metaColor: cs.onSurfaceVariant,
                          bare: true,
                        )
                      : Material(
                          color: isHighlighted
                              ? cs.tertiaryContainer
                              : bgColor,
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
                              onTapQuote: onTapQuote,
                              textColor: textColor,
                              metaColor: textColor,
                              bare: false,
                            ),
                          ),
                        ),
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
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: cs.error,
                  ),
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
        if (message.isMedia)
          ClipRRect(
            borderRadius: AppRadius.all(AppRadius.sm),
            child: ChatMediaPreview(message: message, loader: mediaLoader),
          ),
        if (text != null && text.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: message.isMedia ? AppSpacing.sm : 0),
            child: _MessageText(
              text: text,
              color: textColor,
              bare: bare,
            ),
          ),
        const SizedBox(height: AppSpacing.xxs),
        Align(
          alignment: Alignment.centerRight,
          child: _MetaRow(
            message: message,
            isMine: isMine,
            otherUid: otherUid,
            otherIsOnline: otherIsOnline,
            textColor: metaColor,
          ),
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
    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.schedule_rounded, size: 13, color: color);
      case MessageStatus.failed:
        return Icon(
          Icons.error_outline_rounded,
          size: 14,
          color: Theme.of(context).colorScheme.error,
        );
      case MessageStatus.read:
        // Only "read" is coloured, so a glance distinguishes it from
        // "delivered" without having to count ticks.
        return Icon(
          Icons.done_all_rounded,
          size: 15,
          color: context.chatColors.readTick,
        );
      case MessageStatus.delivered:
        return Icon(Icons.done_all_rounded, size: 15, color: color);
      case MessageStatus.sent:
        return Icon(Icons.done_rounded, size: 15, color: color);
    }
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
            Text(
              preview == null || preview.isEmpty ? '🔒 Message' : preview,
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
  const _TombstoneBubble({required this.isMine, required this.isLastInGroup});

  final bool isMine;
  final bool isLastInGroup;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Align(
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
            Icon(
              Icons.block_rounded,
              size: 15,
              color: cs.onSurfaceVariant,
            ),
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
  });

  final String text;
  final Color color;
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spans = <InlineSpan>[];
    final regex = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);
    var start = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      final raw = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () => launchUrl(Uri.parse(raw), mode: LaunchMode.externalApplication),
            child: Text(
              raw,
              style: (bare
                      ? const TextStyle(fontSize: 44, height: 1.1)
                      : theme.textTheme.bodyLarge)
                  ?.copyWith(
                    color: color,
                    decoration: TextDecoration.underline,
                    decorationColor: color.withValues(alpha: 0.8),
                  ),
            ),
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return SelectableText.rich(
      TextSpan(
        style: bare
            ? const TextStyle(fontSize: 44, height: 1.1)
            : theme.textTheme.bodyLarge?.copyWith(color: color),
        children: spans.isEmpty ? [TextSpan(text: text)] : spans,
      ),
    );
  }
}