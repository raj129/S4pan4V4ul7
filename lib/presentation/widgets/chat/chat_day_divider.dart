import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';
import '../../theme/chat_theme.dart';

/// Pill-shaped "Today / Yesterday / 12 Mar 2024" divider between day runs.
class ChatDayDivider extends StatelessWidget {
  const ChatDayDivider({super.key, required this.date});

  final DateTime date;

  static String labelFor(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final delta = today.difference(day).inDays;

    if (delta == 0) return 'Today';
    if (delta == 1) return 'Yesterday';
    if (delta < 7) return DateFormat('EEEE').format(day);
    if (day.year == today.year) return DateFormat('d MMM').format(day);
    return DateFormat('d MMM yyyy').format(day);
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.chatColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: chat.bubbleTheirs,
            borderRadius: AppRadius.all(AppRadius.pill),
            boxShadow: [
              BoxShadow(
                color: chat.bubbleShadow,
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Text(
            labelFor(date),
            style: AppTypography.overline(
              chat.onBubbleTheirs.withValues(alpha: 0.75),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width "Unread messages" marker inserted above the first unseen message.
class ChatUnreadDivider extends StatelessWidget {
  const ChatUnreadDivider({super.key, this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = count == null || count == 0
        ? 'Unread messages'
        : '$count unread message${count == 1 ? '' : 's'}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.primary.withValues(alpha: 0.35))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(label, style: AppTypography.overline(cs.primary)),
          ),
          Expanded(child: Divider(color: cs.primary.withValues(alpha: 0.35))),
        ],
      ),
    );
  }
}
