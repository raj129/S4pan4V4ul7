import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_attachment_panel.dart';
import 'package:photo_vault/features/chat/presentation/widgets/composer_panel_host.dart';

void main() {
  test('ComposerPanelController enforces mutual exclusion and back-key behavior', () async {
    final controller = ComposerPanelController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    expect(controller.activePanel, ComposerPanel.none);
    expect(controller.isOpen, isFalse);

    // Open emoji panel.
    controller.togglePanel(ComposerPanel.emoji, inputFocus: focusNode);
    expect(controller.activePanel, ComposerPanel.emoji);
    expect(controller.isEmojiOpen, isTrue);
    expect(controller.isAttachmentOpen, isFalse);

    // Switching to attachment closes emoji (never overlaps).
    controller.togglePanel(ComposerPanel.attachment, inputFocus: focusNode);
    expect(controller.activePanel, ComposerPanel.attachment);
    expect(controller.isEmojiOpen, isFalse);
    expect(controller.isAttachmentOpen, isTrue);

    // Switching back to emoji closes attachment.
    controller.togglePanel(ComposerPanel.emoji, inputFocus: focusNode);
    expect(controller.activePanel, ComposerPanel.emoji);

    // Back-key dismissal closes panel without requesting focus.
    controller.closePanel();
    expect(controller.activePanel, ComposerPanel.none);
    expect(focusNode.hasFocus, isFalse);
  });

  test('ComposerPanelController caches keyboard height and guards focus bounce', () async {
    final controller = ComposerPanelController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });

    controller.updateViewInsets(320);
    expect(controller.keyboardHeight, 320);

    // While keyboard height is 320, panel reserves 0 extra height.
    controller.openPanel(ComposerPanel.emoji, inputFocus: focusNode);
    expect(
      controller.currentReservedHeight(
        viewInsetsBottom: 320,
        maxAvailableHeight: 500,
      ),
      0,
    );

    // As keyboard animates down, panel fills the exact remaining height.
    expect(
      controller.currentReservedHeight(
        viewInsetsBottom: 120,
        maxAvailableHeight: 500,
      ),
      200,
    );
    expect(
      controller.currentReservedHeight(
        viewInsetsBottom: 0,
        maxAvailableHeight: 500,
      ),
      320,
    );

    // Focus bounce while unfocusing does not immediately close the panel.
    controller.handleInputFocusChanged(false);
    expect(controller.isEmojiOpen, isTrue);
  });

  testWidgets('ComposerPanelHost switches cleanly between emoji and attachment panels', (
    tester,
  ) async {
    final controller = ComposerPanelController();
    final focusNode = FocusNode();
    addTearDown(() {
      controller.dispose();
      focusNode.dispose();
    });
    String? selectedChoice;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              Expanded(child: TextField(focusNode: focusNode)),
              ComposerPanelHost(
                controller: controller,
                emojiBuilder: (_, height) => SizedBox(
                  key: const ValueKey('test-emoji-panel'),
                  height: height,
                  child: const Text('Emoji Panel'),
                ),
                attachmentBuilder: (_) => ChatAttachmentPanel(
                  options: defaultChatAttachmentOptions(
                    includeAndroidLocationOptions: false,
                  ),
                  onSelect: (choice) {
                    selectedChoice = choice;
                    controller.closePanel();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('test-emoji-panel')), findsNothing);
    expect(find.byKey(const ValueKey('attachment-options-grid')), findsNothing);

    controller.togglePanel(ComposerPanel.emoji, inputFocus: focusNode);
    await tester.pump();
    expect(find.byKey(const ValueKey('test-emoji-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('attachment-options-grid')), findsNothing);

    controller.togglePanel(ComposerPanel.attachment, inputFocus: focusNode);
    await tester.pump();
    expect(find.byKey(const ValueKey('test-emoji-panel')), findsNothing);
    expect(
      find.byKey(const ValueKey('attachment-options-grid')),
      findsOneWidget,
    );

    await tester.tap(find.text('Camera'));
    await tester.pump();
    expect(selectedChoice, 'camera');
    expect(controller.isOpen, isFalse);
    expect(find.byKey(const ValueKey('attachment-options-grid')), findsNothing);
  });
}
