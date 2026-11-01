import '../../domain/entities/chat_message.dart';

/// One rendered row of a conversation: a message or a day divider.
class ThreadItem {
  const ThreadItem.message(
    ChatMessage this.message, {
    required this.isFirstInGroup,
    required this.isLastInGroup,
  }) : divider = null;

  const ThreadItem.divider(DateTime this.divider)
    : message = null,
      isFirstInGroup = false,
      isLastInGroup = false;

  final ChatMessage? message;
  final DateTime? divider;
  final bool isFirstInGroup;
  final bool isLastInGroup;
}

/// The rows for a message window, plus per-row message ordinals.
class ThreadTimeline {
  const ThreadTimeline._(this.items, this.messageOrdinals);

  static const empty = ThreadTimeline._([], []);

  /// Newest first, matching a `reverse: true` list.
  final List<ThreadItem> items;

  /// For each row, how many message rows come before it. Lets the scrollbar
  /// turn a visible row into a history rank without any I/O.
  final List<int> messageOrdinals;

  /// Longest gap between two messages from the same sender that still reads
  /// as one continuous run.
  static const groupWindow = Duration(minutes: 5);

  /// Flattens [msgs] (newest first) into rows.
  ///
  /// Because the list is reversed, `index + 1` is the *older* neighbour and
  /// `index - 1` the *newer* one; grouping and day dividers read that way.
  /// Pure and O(n), so it is cheap to run once per window change and is
  /// unit-tested independently of the screen.
  factory ThreadTimeline.build(
    List<ChatMessage> msgs, {
    bool withDayDividers = true,
  }) {
    final items = <ThreadItem>[];
    final ordinals = <int>[];
    for (var i = 0; i < msgs.length; i++) {
      final msg = msgs[i];
      final older = i + 1 < msgs.length ? msgs[i + 1] : null;
      final newer = i > 0 ? msgs[i - 1] : null;
      final startsDay = older == null || !sameDay(older.sentAt, msg.sentAt);

      ordinals.add(i);
      items.add(
        ThreadItem.message(
          msg,
          // A day divider always breaks a run.
          isFirstInGroup: startsDay || !sameRun(older, msg),
          isLastInGroup: !sameRun(msg, newer),
        ),
      );

      // Appended *after* the message so the reversed list draws it above.
      if (withDayDividers && startsDay) {
        ordinals.add(i + 1);
        items.add(ThreadItem.divider(msg.sentAt));
      }
    }
    return ThreadTimeline._(
      List.unmodifiable(items),
      List.unmodifiable(ordinals),
    );
  }

  static bool sameDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  /// Whether [earlier] and [later] belong to the same visual run.
  static bool sameRun(ChatMessage? earlier, ChatMessage? later) {
    if (earlier == null || later == null) return false;
    if (earlier.senderId != later.senderId) return false;
    if (!sameDay(earlier.sentAt, later.sentAt)) return false;
    return later.sentAt.difference(earlier.sentAt).abs() <= groupWindow;
  }
}
