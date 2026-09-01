import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/message_metadata.dart';
import '../../../domain/entities/message_reply.dart';
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
    this.onDeleteForEveryone,
    this.onReply,
    this.onReact,
    this.onEdit,
    this.onSaveToVault,
    this.onForward,
    this.onTapQuote,
    this.onRetry,
    this.onDiscard,
    this.isHighlighted = false,
  });

  final ChatMessage message;
  final bool isMine;
  final String myUid;
  final String otherUid;
  final bool otherIsOnline;
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

  /// Briefly tinted after the user jumps here from a quote.
  final bool isHighlighted;

  @override
  Widget build(BuildContext context) {
    if (message.deletedForEveryone) {
      return _TombstoneBubble(isMine: isMine);
    }

    final cs = Theme.of(context).colorScheme;
    final bgColor = isMine ? cs.primary : cs.surfaceContainerHigh;
    final textColor = isMine ? cs.onPrimary : cs.onSurface;
    final grouped = message.groupedReactions;

    // Emoji-only messages render bare and oversized, as in WhatsApp.
    final bare = message.isEmojiOnly;
    final text = message.localDecryptedText;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Dismissible(
            key: ValueKey('swipe_${message.messageId}'),
            // Swipe toward the centre of the screen to reply, in the direction
            // that feels natural for each side of the conversation.
            direction: onReply == null
                ? DismissDirection.none
                : (isMine
                      ? DismissDirection.endToStart
                      : DismissDirection.startToEnd),
            confirmDismiss: (_) async {
              onReply?.call();
              // Never actually dismiss: the swipe is a shortcut, not a delete.
              return false;
            },
            background: const _ReplySwipeBackground(alignEnd: false),
            secondaryBackground: const _ReplySwipeBackground(alignEnd: true),
            child: GestureDetector(
              onLongPress: () => _showActionSheet(context),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
                padding: bare
                    ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
                    : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.74,
                ),
                decoration: BoxDecoration(
                  color: isHighlighted
                      ? cs.tertiaryContainer
                      : (bare ? Colors.transparent : bgColor),
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(isMine ? 18 : 4),
                    bottomRight: Radius.circular(isMine ? 4 : 18),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isForwarded)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.shortcut,
                              size: 12,
                              color: textColor.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'Forwarded',
                              style: TextStyle(
                                fontSize: 11,
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
                        onTap: onTapQuote == null
                            ? null
                            : () => onTapQuote!(message.replyTo!.messageId),
                      ),
                    if (message.isMedia)
                      ChatMediaPreview(
                        message: message,
                        loader: mediaLoader,
                      ),
                    if (text != null && text.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(
                          top: message.isMedia ? 6 : 0,
                        ),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: bare ? null : textColor,
                            fontSize: bare ? 40 : null,
                          ),
                        ),
                      ),
                    const SizedBox(height: 2),
                    Align(
                      alignment: Alignment.centerRight,
                      child: _MetaRow(
                        message: message,
                        isMine: isMine,
                        otherUid: otherUid,
                        otherIsOnline: otherIsOnline,
                        textColor: bare ? cs.onSurfaceVariant : textColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (grouped.isNotEmpty)
            _ReactionRow(grouped: grouped, myUid: myUid, onTap: onReact),
        ],
      ),
    );
  }

  void _showActionSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.status == MessageStatus.failed) ...[
              if (onRetry != null)
                ListTile(
                  leading: const Icon(Icons.refresh),
                  title: const Text('Try again'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onRetry!();
                  },
                ),
              if (onDiscard != null)
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Discard unsent message'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    onDiscard!();
                  },
                ),
              const Divider(height: 1),
            ],
            if (onReact != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
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
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_outlined),
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
            if (onForward != null)
              ListTile(
                leading: const Icon(Icons.shortcut),
                title: const Text('Forward'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onForward!();
                },
              ),
            if (onSaveToVault != null)
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Save to vault'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  onSaveToVault!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete for me'),
              onTap: () {
                Navigator.pop(sheetContext);
                onDeleteForMe();
              },
            ),
            if (onDeleteForEveryone != null)
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Delete for everyone'),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Colors.transparent,
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 24)),
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
    final faded = textColor.withValues(alpha: 0.7);
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
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              'edited',
              style: TextStyle(fontSize: 10, color: faded),
            ),
          ),
        Text(
          DateFormat.jm().format(message.sentAt.toLocal()),
          style: TextStyle(fontSize: 10, color: faded),
        ),
        if (isMine) ...[
          const SizedBox(width: 4),
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
        return Icon(Icons.schedule, size: 12, color: color);
      case MessageStatus.failed:
        return Icon(
          Icons.error_outline,
          size: 13,
          color: Theme.of(context).colorScheme.error,
        );
      case MessageStatus.read:
        // Only "read" is coloured, so a glance distinguishes it from
        // "delivered" without having to count ticks.
        return const Icon(Icons.done_all, size: 14, color: Color(0xFF34B7F1));
      case MessageStatus.delivered:
        return Icon(Icons.done_all, size: 14, color: color);
      case MessageStatus.sent:
        return Icon(Icons.done, size: 14, color: color);
    }
  }
}

/// The quoted preview shown above a reply.
class _QuotedHeader extends StatelessWidget {
  const _QuotedHeader({
    required this.reply,
    required this.isMine,
    required this.myUid,
    this.onTap,
  });

  final MessageReply reply;
  final bool isMine;
  final String myUid;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = isMine ? cs.onPrimary : cs.primary;
    final label = reply.senderId == myUid ? 'You' : 'Them';
    final preview = reply.localDecryptedPreview?.trim();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border(left: BorderSide(color: accent, width: 3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            Text(
              preview == null || preview.isEmpty ? '🔒 Message' : preview,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: (isMine ? cs.onPrimary : cs.onSurface).withValues(
                  alpha: 0.8,
                ),
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
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10, bottom: 4),
      child: Wrap(
        spacing: 4,
        children: [
          for (final entry in grouped.entries)
            GestureDetector(
              onTap: onTap == null ? null : () => onTap!(entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: entry.value.contains(myUid)
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  entry.value.length > 1
                      ? '${entry.key} ${entry.value.length}'
                      : entry.key,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// "This message was deleted" placeholder.
///
/// The document is kept rather than removed so the message does not silently
/// vanish from the other side of the conversation.
class _TombstoneBubble extends StatelessWidget {
  const _TombstoneBubble({required this.isMine});

  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              'This message was deleted',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: cs.onSurfaceVariant,
                fontSize: 13,
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
    return Align(
      alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Icon(Icons.reply, size: 20),
      ),
    );
  }
}
