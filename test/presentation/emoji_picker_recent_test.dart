import 'dart:async';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/storage/shared_preferences_readiness.dart';
import 'package:photo_vault/features/chat/presentation/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('waits for shared preferences before mounting emoji picker', (
    tester,
  ) async {
    final readiness = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemedEmojiPicker(
            preferencesReadiness: SharedPreferencesReadiness(
              load: () => readiness.future,
            ),
            onEmojiSelected: (_, _) {},
          ),
        ),
      ),
    );

    expect(find.text('Loading emoji...'), findsOneWidget);
    expect(find.byType(EmojiPicker), findsNothing);

    readiness.complete();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byType(EmojiPicker), findsOneWidget);
  });

  testWidgets('retries shared preferences failure without mounting picker', (
    tester,
  ) async {
    var attempts = 0;
    final readiness = SharedPreferencesReadiness(
      load: () async {
        attempts++;
        if (attempts == 1) throw StateError('plugin unavailable');
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemedEmojiPicker(
            preferencesReadiness: readiness,
            onEmojiSelected: (_, _) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(EmojiPicker), findsNothing);
    expect(find.text('Emoji history is unavailable.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.byType(EmojiPicker), findsOneWidget);
  });

  testWidgets('layout height changes do not invalidate emoji categories', (
    tester,
  ) async {
    Future<void> pumpPicker(double height) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ThemedEmojiPicker(
              height: height,
              searchHeight: height * 0.7,
              onEmojiSelected: (_, _) {},
            ),
          ),
        ),
      );
    }

    await pumpPicker(280);
    await tester.pumpAndSettle();

    final initialConfig = tester
        .widget<EmojiPicker>(find.byType(EmojiPicker))
        .config;

    await pumpPicker(360);
    await tester.pumpAndSettle();

    final resizedConfig = tester
        .widget<EmojiPicker>(find.byType(EmojiPicker))
        .config;
    expect(initialConfig.height, isNull);
    expect(resizedConfig, initialConfig);
    expect(tester.takeException(), isNull);
  });

  testWidgets('emoji selected from search appears in recent emojis', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? selectedEmoji;
    final composerController = TextEditingController();
    addTearDown(composerController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThemedEmojiPicker(
            textEditingController: composerController,
            showBackspace: false,
            onEmojiSelected: (_, emoji) => selectedEmoji = emoji.emoji,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.search));
    await tester.pumpAndSettle();
    final searchField = find.byType(TextField);
    final backspaceButton = find.ancestor(
      of: find.byTooltip('Backspace'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(backspaceButton).onPressed, isNotNull);
    await tester.tap(backspaceButton);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(searchField).controller!.text, isEmpty);

    await tester.enterText(searchField, '😀😂');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(searchField).controller!.text, '😀😂');
    await tester.tap(backspaceButton);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(searchField).controller!.text, '😀');

    await tester.tap(
      find.byWidgetPredicate((widget) => widget is Text && widget.data == '😀'),
    );
    await tester.pumpAndSettle();

    expect(selectedEmoji, '😀');
    expect(composerController.text, '😀');

    await tester.enterText(searchField, '');
    await tester.pumpAndSettle();
    expect(find.text('😀'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.access_time));
    await tester.pumpAndSettle();
    expect(find.text('😀'), findsOneWidget);
  });
}
