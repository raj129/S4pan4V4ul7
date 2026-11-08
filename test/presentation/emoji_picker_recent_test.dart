import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/presentation/widgets/message_bubble.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
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
