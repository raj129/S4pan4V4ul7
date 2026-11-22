import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/presentation/widgets/rich_note_controller.dart';

void main() {
  test('toggleStyle applies bold/strikethrough with zero visible markers and round-trips to Markdown', () {
    final ctrl = RichNoteTextEditingController.fromMarkdown('hello world');
    addTearDown(ctrl.dispose);

    ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    ctrl.toggleStyle(bold: true);
    expect(ctrl.text, 'hello world');
    expect(ctrl.toMarkdown(), '**hello** world');

    ctrl.toggleStyle(bold: true);
    expect(ctrl.text, 'hello world');
    expect(ctrl.toMarkdown(), 'hello world');

    ctrl.selection = const TextSelection(baseOffset: 6, extentOffset: 11);
    ctrl.toggleStyle(strikethrough: true);
    expect(ctrl.text, 'hello world');
    expect(ctrl.toMarkdown(), 'hello ~~world~~');
  });

  test('numbered list auto-continues and auto-arranges on Enter', () {
    final ctrl = RichNoteTextEditingController(text: '1. First');
    addTearDown(ctrl.dispose);

    const prev = TextEditingValue(
      text: '1. First',
      selection: TextSelection.collapsed(offset: 8),
    );
    const next = TextEditingValue(
      text: '1. First\n',
      selection: TextSelection.collapsed(offset: 9),
    );
    ctrl.value = next;
    final handled = ctrl.handleListAutoArrange(prev, next);

    expect(handled, isTrue);
    expect(ctrl.text, '1. First\n2. ');
    expect(ctrl.selection.baseOffset, 12);
  });

  test('toggleNumberedList renumbers lines cleanly', () {
    final ctrl = RichNoteTextEditingController(text: 'Alpha\nBeta');
    addTearDown(ctrl.dispose);

    ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 10);
    ctrl.toggleNumberedList();
    expect(ctrl.text, '1. Alpha\n2. Beta');

    ctrl.selection = const TextSelection(baseOffset: 0, extentOffset: 16);
    ctrl.toggleNumberedList();
    expect(ctrl.text, 'Alpha\nBeta');
  });

  test('extractUrls finds markdown links and bare URLs', () {
    final urls = RichNoteTextEditingController.extractUrls(
      'Check [Docs](https://flutter.dev) and https://example.com/path',
    );
    expect(urls, ['https://flutter.dev', 'https://example.com/path']);
  });

  test('typing with pending styles without spaces coalesces spans and round-trips cleanly', () {
    final ctrl = RichNoteTextEditingController(text: '');
    addTearDown(ctrl.dispose);

    void typeChars(String chars) {
      for (final ch in chars.split('')) {
        final nextText = '${ctrl.text}$ch';
        ctrl.value = TextEditingValue(
          text: nextText,
          selection: TextSelection.collapsed(offset: nextText.length),
        );
      }
    }

    // Plain "bold"
    typeChars('bold');
    // Bold "bold"
    ctrl.toggleStyle(bold: true);
    expect(ctrl.isBoldActive, isTrue);
    typeChars('bold');
    // Switch to Italic only
    ctrl.toggleStyle(bold: true);
    expect(ctrl.isBoldActive, isFalse);
    ctrl.toggleStyle(italic: true);
    expect(ctrl.isItalicActive, isTrue);
    typeChars('Italic');
    // Add Bold (Bold+Italic)
    ctrl.toggleStyle(bold: true);
    expect(ctrl.isBoldActive, isTrue);
    expect(ctrl.isItalicActive, isTrue);
    typeChars('BoldItalic');
    // Add Strikethrough (Bold+Italic+Strike)
    ctrl.toggleStyle(strikethrough: true);
    typeChars('BoldItalicStrick');
    // Turn off Bold and Strike, keep Italic
    ctrl.toggleStyle(bold: true);
    ctrl.toggleStyle(strikethrough: true);
    expect(ctrl.isBoldActive, isFalse);
    expect(ctrl.isStrikethroughActive, isFalse);
    expect(ctrl.isItalicActive, isTrue);
    typeChars(',italic');

    expect(ctrl.text, 'boldboldItalicBoldItalicBoldItalicStrick,italic');
    // Spans should be coalesced (5 styled spans, not 47 per-char spans).
    expect(ctrl.spans.length, 5);

    final md1 = ctrl.toMarkdown();
    // Round-trip through parseMarkdown -> toMarkdown multiple times must be stable
    final reparsed1 = RichNoteTextEditingController.fromMarkdown(md1);
    addTearDown(reparsed1.dispose);
    expect(reparsed1.text, 'boldboldItalicBoldItalicBoldItalicStrick,italic');
    expect(reparsed1.text.contains('*'), isFalse);
    expect(reparsed1.text.contains('~'), isFalse);

    final md2 = reparsed1.toMarkdown();
    expect(md2, md1);

    final reparsed2 = RichNoteTextEditingController.fromMarkdown(md2);
    addTearDown(reparsed2.dispose);
    expect(reparsed2.text, 'boldboldItalicBoldItalicBoldItalicStrick,italic');
    expect(reparsed2.spans.length, reparsed1.spans.length);
  });

  test('nested bold+italic+strikethrough and lists round-trip without leaking markers', () {
    const raw =
        '***~~AllThree~~*** **~~BoldStrike~~** *~~ItalicStrike~~*\n'
        '- list\n'
        '- list2\n'
        '1. one\n'
        '2. two';
    final ctrl = RichNoteTextEditingController.fromMarkdown(raw);
    addTearDown(ctrl.dispose);

    expect(
      ctrl.text,
      'AllThree BoldStrike ItalicStrike\n- list\n- list2\n1. one\n2. two',
    );
    expect(ctrl.spans.first.bold, isTrue);
    expect(ctrl.spans.first.italic, isTrue);
    expect(ctrl.spans.first.strikethrough, isTrue);

    final out = ctrl.toMarkdown();
    final again = RichNoteTextEditingController.fromMarkdown(out);
    addTearDown(again.dispose);
    expect(again.text, ctrl.text);
    expect(again.toMarkdown(), out);
  });

  testWidgets('buildReadOnlyRichText renders plain formatted text without raw markers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => RichNoteTextEditingController.buildReadOnlyRichText(
              context,
              text: 'bold**bold***Italic****BoldItalic******~~Strick~~***',
            ),
          ),
        ),
      ),
    );
    expect(
      find.text('boldboldItalicBoldItalicStrick', findRichText: true),
      findsOneWidget,
    );
  });
}
