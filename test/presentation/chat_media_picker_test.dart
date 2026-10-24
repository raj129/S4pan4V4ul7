import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/data/repositories/local_sticker_pack_repository.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_media_picker.dart';

class _MemoryStickerKeyStore implements StickerKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('chat-media-picker-test-');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  testWidgets('offers Emoji, Stickers, and GIF tabs in one panel', (
    tester,
  ) async {
    String? insertedEmoji;
    var backspacePresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatMediaPickerPanel(
            stickerPack: LocalStickerPackRepository(
              userId: 'test-user',
              rootDirectory: root,
              keyStore: _MemoryStickerKeyStore(),
            ),
            buildEmojiPicker: (_) => const Center(child: Text('Emoji grid')),
            onSend: (_, _, _) async {},
            onInsertEmoji: (emoji) => insertedEmoji = emoji,
            onBackspace: () => backspacePresses++,
            onClose: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Emoji'), findsOneWidget);
    expect(find.byTooltip('Stickers'), findsOneWidget);
    expect(find.byTooltip('GIFs'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Emoji grid'), findsOneWidget);
    expect(
      tester.getRect(find.byTooltip('Search emoji')).left,
      lessThan(tester.getRect(find.byTooltip('Emoji')).left),
    );
    expect(
      tester.getRect(find.byTooltip('Backspace')).left,
      greaterThan(tester.getRect(find.byTooltip('GIFs')).left),
    );

    await tester.tap(find.byTooltip('Backspace'));
    expect(backspacePresses, 1);

    await tester.tap(find.byTooltip('Search emoji'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    final searchField = tester.getRect(find.byType(TextField));
    final emojiTab = tester.getRect(find.byTooltip('Emoji'));
    final gifTab = tester.getRect(find.byTooltip('GIFs'));
    expect(searchField.contains(emojiTab.center), isTrue);
    expect(searchField.contains(gifTab.center), isTrue);
    final backspaceButton = find.ancestor(
      of: find.byTooltip('Backspace'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(backspaceButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'smiling eyes');
    await tester.pumpAndSettle();
    expect(find.text('😊'), findsOneWidget);
    await tester.tap(find.text('😊'));
    expect(insertedEmoji, '😊');

    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Emoji grid'), findsOneWidget);

    await tester.drag(
      find.byKey(const ValueKey('chat-media-pages')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('My stickers'), findsOneWidget);
    expect(tester.widget<IconButton>(backspaceButton).onPressed, isNull);

    await tester.drag(
      find.byKey(const ValueKey('chat-media-pages')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('GIPHY_API_KEY is not configured'),
      findsOneWidget,
    );
    expect(find.text('Powered by GIPHY'), findsOneWidget);
  });
}
