import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/presentation/screens/thread_timeline.dart';

ChatMessage _msg(String id, String sender, DateTime at) => ChatMessage(
  messageId: id,
  threadId: 't',
  senderId: sender,
  encryptedText: '',
  sentAt: at,
  deletedFor: const [],
);

void main() {
  final day1 = DateTime(2026, 10, 31, 22, 0);
  final day2 = DateTime(2026, 11, 1, 9, 0);

  test('empty input gives an empty timeline', () {
    final t = ThreadTimeline.build(const []);
    expect(t.items, isEmpty);
    expect(t.messageOrdinals, isEmpty);
  });

  test('inserts a day divider above the first message of each day', () {
    // Newest first.
    final msgs = [
      _msg('c', 'a', day2.add(const Duration(minutes: 1))),
      _msg('b', 'a', day2),
      _msg('a', 'a', day1),
    ];
    final t = ThreadTimeline.build(msgs);
    final kinds = t.items
        .map((i) => i.divider != null ? 'D' : i.message!.messageId)
        .toList();
    expect(kinds, ['c', 'b', 'D', 'a', 'D']);
  });

  test('message ordinals count the message rows before each row', () {
    final msgs = [
      _msg('c', 'a', day2.add(const Duration(minutes: 1))),
      _msg('b', 'a', day2),
      _msg('a', 'a', day1),
    ];
    final t = ThreadTimeline.build(msgs);
    expect(t.messageOrdinals, [0, 1, 2, 2, 3]);
  });

  test('groups consecutive messages from one sender within the window', () {
    final msgs = [
      _msg('3', 'bob', day2.add(const Duration(minutes: 20))),
      _msg('2', 'alice', day2.add(const Duration(minutes: 2))),
      _msg('1', 'alice', day2),
    ];
    final items = ThreadTimeline.build(
      msgs,
      withDayDividers: false,
    ).items.toList();
    // alice's 2 messages form one run: '1' starts it, '2' ends it.
    expect(items[2].isFirstInGroup, isTrue);
    expect(items[2].isLastInGroup, isFalse);
    expect(items[1].isFirstInGroup, isFalse);
    expect(items[1].isLastInGroup, isTrue);
    // bob's message is its own run.
    expect(items[0].isFirstInGroup && items[0].isLastInGroup, isTrue);
  });

  test('a gap longer than the group window breaks the run', () {
    final msgs = [
      _msg('2', 'alice', day2.add(const Duration(minutes: 6))),
      _msg('1', 'alice', day2),
    ];
    final items = ThreadTimeline.build(msgs, withDayDividers: false).items;
    expect(items[0].isFirstInGroup, isTrue);
    expect(items[1].isLastInGroup, isTrue);
  });
}
