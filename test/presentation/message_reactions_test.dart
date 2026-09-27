import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/presentation/widgets/chat/chat_media_preview.dart';
import 'package:photo_vault/presentation/widgets/chat/message_bubble.dart';

class _NoMediaLoader implements ChatMediaLoader {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

ChatMessage _message({Map<String, String> reactions = const {}}) => ChatMessage(
  messageId: 'm1',
  threadId: 't1',
  senderId: 'other',
  encryptedText: 'x',
  sentAt: DateTime.utc(2024),
  deletedFor: const [],
  reactions: reactions,
).withDecryptedText('hello');

void main() {
  Future<List<String>> pumpBubble(
    WidgetTester tester, {
    Map<String, String> reactions = const {},
  }) async {
    final reacted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _message(reactions: reactions),
            isMine: false,
            myUid: 'me',
            otherUid: 'other',
            mediaLoader: _NoMediaLoader(),
            onDeleteForMe: () {},
            onReact: reacted.add,
          ),
        ),
      ),
    );
    // Press the bubble's padding: the text itself is selectable and claims
    // long presses for text selection.
    final bubble = find
        .ancestor(of: find.text('hello'), matching: find.byType(Material))
        .first;
    await tester.longPressAt(tester.getTopLeft(bubble) + const Offset(6, 4));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget, reason: 'action sheet');
    return reacted;
  }

  testWidgets('"+" opens the full picker and reacts with the chosen emoji', (
    tester,
  ) async {
    final reacted = await pumpBubble(tester);

    await tester.tap(find.byTooltip('More reactions'));
    await tester.pumpAndSettle();
    final picker = find.byType(EmojiPicker);
    expect(picker, findsOneWidget);

    tester.widget<EmojiPicker>(picker).onEmojiSelected!(
      Category.ANIMALS,
      const Emoji('🦄', 'unicorn'),
    );
    await tester.pumpAndSettle();

    expect(reacted, ['🦄']);
    expect(find.byType(EmojiPicker), findsNothing);
  });

  testWidgets('a custom reaction is shown highlighted in the "+" slot', (
    tester,
  ) async {
    await pumpBubble(tester, reactions: const {'me': '🦄'});

    expect(
      find.descendant(
        of: find.byTooltip('More reactions'),
        matching: find.text('🦄'),
      ),
      findsOneWidget,
    );
  });
}
