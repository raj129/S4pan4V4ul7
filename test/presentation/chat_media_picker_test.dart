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

  testWidgets('offers a draggable Emoji, Stickers, and GIF picker', (
    tester,
  ) async {
    String? insertedEmoji;
    var backspacePresses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showChatMediaPickerSheet(
                  context,
                  stickerPack: LocalStickerPackRepository(
                    userId: 'test-user',
                    rootDirectory: root,
                    keyStore: _MemoryStickerKeyStore(),
                  ),
                  buildEmojiPicker: (_) =>
                      const Center(child: Text('Emoji grid')),
                  composer: const SizedBox(
                    key: ValueKey('visible-chat-composer'),
                    height: 56,
                    child: Center(child: Text('Draft stays visible')),
                  ),
                  onSend: (_, _, _) async {},
                  onInsertEmoji: (emoji) => insertedEmoji = emoji,
                  onBackspace: () => backspacePresses++,
                ),
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatMediaPickerPanel), findsOneWidget);
    expect(find.text('Draft stays visible'), findsOneWidget);
    expect(
      tester
          .getRect(find.byKey(const ValueKey('visible-chat-composer')))
          .bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(ChatMediaPickerPanel)).top),
    );
    expect(find.byTooltip('Emoji'), findsOneWidget);
    expect(find.byTooltip('Stickers'), findsOneWidget);
    expect(find.byTooltip('GIFs'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Emoji grid'), findsOneWidget);
    expect(find.byTooltip('Close media picker'), findsNothing);
    expect(
      tester.getRect(find.byTooltip('Search emoji')).left,
      lessThan(tester.getRect(find.byTooltip('Emoji')).left),
    );
    expect(
      tester.getRect(find.byTooltip('Backspace')).left,
      greaterThan(tester.getRect(find.byTooltip('GIFs')).left),
    );
    final tabBounds = Rect.fromLTRB(
      tester.getRect(find.byTooltip('Emoji')).left,
      tester.getRect(find.byTooltip('Emoji')).top,
      tester.getRect(find.byTooltip('GIFs')).right,
      tester.getRect(find.byTooltip('GIFs')).bottom,
    );
    expect(
      tabBounds.center.dx,
      closeTo(tester.getRect(find.byType(ChatMediaPickerPanel)).center.dx, 3),
    );

    await tester.tap(find.byKey(const ValueKey('picker-tab-gifs')));
    await tester.pumpAndSettle();
    expect(find.text('Powered by GIPHY'), findsOneWidget);
    expect(
      find.textContaining('GIPHY_API_KEY is not configured'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('picker-tab-emoji')));
    await tester.pumpAndSettle();
    expect(find.text('Emoji grid'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('picker-tab-stickers')));
    await tester.pumpAndSettle();
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('My stickers'), findsOneWidget);
    expect(tester.getRect(find.text('Explore')).height, lessThan(20));
    expect(tester.getRect(find.text('My stickers')).height, lessThan(20));
    expect(
      find.textContaining('GIPHY_API_KEY is not configured'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('picker-tab-gifs')));
    await tester.pumpAndSettle();
    expect(find.text('Powered by GIPHY'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('picker-tab-emoji')));
    await tester.pumpAndSettle();
    expect(find.text('Emoji grid'), findsOneWidget);

    final initialHeight = tester
        .getSize(find.byType(ChatMediaPickerPanel))
        .height;
    await tester.drag(
      find.byKey(const ValueKey('picker-drag-handle')),
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(
      tester.getSize(find.byType(ChatMediaPickerPanel)).height,
      greaterThan(initialHeight + 50),
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

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatMediaPickerPanel), findsNothing);
  });
}
