import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/entities/message_metadata.dart';
import 'package:photo_vault/domain/repositories/message_repository.dart';
import 'package:photo_vault/presentation/widgets/chat/chat_media_preview.dart';
import 'package:photo_vault/presentation/widgets/chat/animated_emoji.dart';
import 'package:photo_vault/presentation/widgets/chat/message_bubble.dart';

class _NoMediaRepository implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _TestMediaLoader extends ChatMediaLoader {
  _TestMediaLoader()
    : super(
        mediaRepository: _NoMediaRepository(),
        cryptoService: ChatCryptoService(),
      );

  @override
  Future<Uint8List> load({
    required String threadId,
    required String storagePath,
  }) async => Uint8List.fromList([0]);
}

ChatMessage _message({
  Map<String, String> reactions = const {},
  String text = 'hello',
  MessageType? mediaType,
}) => ChatMessage(
  messageId: 'm1',
  threadId: 't1',
  senderId: 'other',
  encryptedText: 'x',
  sentAt: DateTime.utc(2024),
  deletedFor: const [],
  reactions: reactions,
  mediaRef: mediaType == null ? null : 'media',
  mediaType: mediaType,
).withDecryptedText(text);

void main() {
  Future<List<String>> pumpBubble(
    WidgetTester tester, {
    Map<String, String> reactions = const {},
    String text = 'hello',
    MessageType? mediaType,
  }) async {
    final reacted = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _message(
              reactions: reactions,
              text: text,
              mediaType: mediaType,
            ),
            isMine: false,
            myUid: 'me',
            otherUid: 'other',
            mediaLoader: _TestMediaLoader(),
            onDeleteForMe: () {},
            onReact: reacted.add,
            onSaveToVault: mediaType == null ? null : () {},
          ),
        ),
      ),
    );
    // Press the bubble's padding: the text itself is selectable and claims
    // long presses for text selection.
    final target = mediaType != null
        ? find.byType(ChatMediaPreview)
        : text == 'hello'
        ? find.text('hello')
        : find.byType(AnimatedEmojiText);
    final bubble = mediaType != null || text != 'hello'
        ? target
        : find.ancestor(of: target, matching: find.byType(Material)).first;
    if (text == 'hello' && mediaType == null) {
      await tester.longPressAt(tester.getTopLeft(bubble) + const Offset(6, 4));
    } else {
      await tester.longPress(bubble);
    }
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

  testWidgets('long-pressing a single emoji opens the action sheet', (
    tester,
  ) async {
    await pumpBubble(tester, text: '👍');

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
  });

  testWidgets('long-pressing an image opens the action sheet', (tester) async {
    await pumpBubble(tester, mediaType: MessageType.image);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Save to vault'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
  });

  testWidgets('long-pressing a video opens the action sheet', (tester) async {
    await pumpBubble(tester, mediaType: MessageType.video);

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
  });

  testWidgets('offline outgoing message shows a waiting indicator', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MessageBubble(
            message: _message().copyWith(status: MessageStatus.failed),
            isMine: true,
            myUid: 'me',
            otherUid: 'other',
            isOffline: true,
            mediaLoader: _TestMediaLoader(),
            onDeleteForMe: () {},
          ),
        ),
      ),
    );

    expect(find.text('Waiting for connection'), findsOneWidget);
    expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
  });
}
