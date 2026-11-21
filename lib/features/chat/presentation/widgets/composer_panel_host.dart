import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bottom panels that can be hosted inline below the chat composer.
///
/// Only one panel can be active at a time, guaranteeing that emoji,
/// attachment, and keyboard views never overlap.
enum ComposerPanel { none, emoji, attachment }

/// Coordinates inline bottom panels (`emoji`, `attachment`, etc.) with the
/// software keyboard so transitions stay smooth and race-free.
class ComposerPanelController extends ChangeNotifier {
  static const double defaultKeyboardHeight = 300.0;
  static const double minPanelHeight = 220.0;
  static const double maxKeyboardHeight = 440.0;
  static const Duration _focusGuardDuration = Duration(milliseconds: 180);
  static const Duration _keyboardSwitchDuration = Duration(milliseconds: 220);

  ComposerPanel _activePanel = ComposerPanel.none;
  double _keyboardHeight = defaultKeyboardHeight;
  double _emojiExtraHeight = 0.0;
  double _keyboardPlaceholderHeight = 0.0;
  bool _suppressFocusClose = false;
  bool _switchingToKeyboard = false;
  Timer? _focusGuardTimer;
  Timer? _keyboardSwitchTimer;

  ComposerPanel get activePanel => _activePanel;
  bool get isOpen => _activePanel != ComposerPanel.none;
  bool get isEmojiOpen => _activePanel == ComposerPanel.emoji;
  bool get isAttachmentOpen => _activePanel == ComposerPanel.attachment;
  double get keyboardHeight => _keyboardHeight;

  double targetEmojiHeight(double maxAvailableHeight) {
    final base = _keyboardHeight.clamp(
      minPanelHeight,
      math.max(minPanelHeight, maxAvailableHeight),
    );
    return (base + _emojiExtraHeight).clamp(
      minPanelHeight,
      math.max(minPanelHeight, maxAvailableHeight),
    );
  }

  double currentReservedHeight({
    required double viewInsetsBottom,
    required double maxAvailableHeight,
    double? attachmentHeight,
  }) {
    if (_activePanel == ComposerPanel.none) {
      if (_switchingToKeyboard) {
        return math.max(0.0, _keyboardPlaceholderHeight - viewInsetsBottom);
      }
      return 0.0;
    }
    final target = switch (_activePanel) {
      ComposerPanel.emoji => targetEmojiHeight(maxAvailableHeight),
      ComposerPanel.attachment =>
        attachmentHeight ??
            _keyboardHeight.clamp(
              minPanelHeight,
              math.max(minPanelHeight, maxAvailableHeight),
            ),
      ComposerPanel.none => 0.0,
    };
    return math.max(0.0, target - viewInsetsBottom);
  }

  /// Updates the cached keyboard height from `MediaQuery.viewInsetsOf(context).bottom`.
  void updateViewInsets(double bottomInset) {
    if (bottomInset > 100) {
      final clamped = bottomInset.clamp(minPanelHeight, maxKeyboardHeight);
      if ((clamped - _keyboardHeight).abs() > 1.0) {
        _keyboardHeight = clamped;
      }
      if (_switchingToKeyboard) {
        _switchingToKeyboard = false;
        _keyboardPlaceholderHeight = 0.0;
        _keyboardSwitchTimer?.cancel();
        notifyListeners();
      }
    }
  }

  /// Opens [panel], unfocusing [inputFocus] without allowing the async
  /// focus-loss transition to bounce the panel closed.
  void openPanel(ComposerPanel panel, {required FocusNode inputFocus}) {
    if (panel == ComposerPanel.none) {
      closePanel();
      return;
    }
    _keyboardSwitchTimer?.cancel();
    _switchingToKeyboard = false;
    _keyboardPlaceholderHeight = 0.0;

    if (inputFocus.hasFocus) {
      _suppressFocusClose = true;
      _focusGuardTimer?.cancel();
      _focusGuardTimer = Timer(_focusGuardDuration, () {
        _suppressFocusClose = false;
      });
      inputFocus.unfocus();
    } else {
      _suppressFocusClose = false;
    }

    if (_activePanel != panel) {
      if (panel != ComposerPanel.emoji) {
        _emojiExtraHeight = 0.0;
      }
      _activePanel = panel;
      notifyListeners();
    }
  }

  /// Toggles [panel]:
  /// - Tapping `emoji` while open switches back to the keyboard (WhatsApp-style).
  /// - Tapping `attachment` while open closes it without opening the keyboard.
  void togglePanel(ComposerPanel panel, {required FocusNode inputFocus}) {
    if (_activePanel == panel) {
      if (panel == ComposerPanel.emoji) {
        switchToKeyboard(inputFocus: inputFocus);
      } else {
        closePanel();
      }
      return;
    }
    openPanel(panel, inputFocus: inputFocus);
  }

  /// Closes the active panel and focuses [inputFocus] to bring up the keyboard,
  /// keeping the composer steady while the IME animates in.
  void switchToKeyboard({required FocusNode inputFocus}) {
    _focusGuardTimer?.cancel();
    _suppressFocusClose = false;

    if (_activePanel != ComposerPanel.none) {
      _keyboardPlaceholderHeight = _activePanel == ComposerPanel.emoji
          ? _keyboardHeight + _emojiExtraHeight
          : _keyboardHeight;
      _switchingToKeyboard = true;
      _keyboardSwitchTimer?.cancel();
      _keyboardSwitchTimer = Timer(_keyboardSwitchDuration, () {
        if (_switchingToKeyboard) {
          _switchingToKeyboard = false;
          _keyboardPlaceholderHeight = 0.0;
          notifyListeners();
        }
      });
      _activePanel = ComposerPanel.none;
      _emojiExtraHeight = 0.0;
      notifyListeners();
    }

    if (!inputFocus.hasFocus) {
      inputFocus.requestFocus();
    }
  }

  /// Dismisses any open panel without focusing the composer (Back-key behavior).
  void closePanel() {
    _focusGuardTimer?.cancel();
    _keyboardSwitchTimer?.cancel();
    _suppressFocusClose = false;
    final changed =
        _activePanel != ComposerPanel.none ||
        _switchingToKeyboard ||
        _emojiExtraHeight != 0.0;
    _activePanel = ComposerPanel.none;
    _switchingToKeyboard = false;
    _keyboardPlaceholderHeight = 0.0;
    _emojiExtraHeight = 0.0;
    if (changed) {
      notifyListeners();
    }
  }

  /// Call from the composer's [FocusNode] listener so tapping into the text
  /// field closes any open panel cleanly.
  void handleInputFocusChanged(bool hasFocus) {
    if (!hasFocus) {
      if (_suppressFocusClose) {
        _suppressFocusClose = false;
        _focusGuardTimer?.cancel();
      }
      return;
    }
    if (!_suppressFocusClose && _activePanel != ComposerPanel.none) {
      closePanel();
    }
  }

  void adjustEmojiHeight(double deltaY, {required double maxAvailableHeight}) {
    final maxExtra = math.max(0.0, maxAvailableHeight - _keyboardHeight);
    final next = (_emojiExtraHeight - deltaY).clamp(0.0, maxExtra);
    if ((next - _emojiExtraHeight).abs() > 0.5) {
      _emojiExtraHeight = next;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _focusGuardTimer?.cancel();
    _keyboardSwitchTimer?.cancel();
    super.dispose();
  }
}

/// Hosts the active [ComposerPanel] inline below the chat composer, sizing it
/// smoothly against `MediaQuery.viewInsetsOf(context).bottom`.
class ComposerPanelHost extends StatelessWidget {
  const ComposerPanelHost({
    super.key,
    required this.controller,
    required this.emojiBuilder,
    required this.attachmentBuilder,
    this.maxHeightFraction = 0.72,
  });

  final ComposerPanelController controller;
  final Widget Function(BuildContext context, double height) emojiBuilder;
  final WidgetBuilder attachmentBuilder;
  final double maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final viewInsetsBottom = MediaQuery.viewInsetsOf(context).bottom;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxAvailableHeight = math.max(
      ComposerPanelController.minPanelHeight,
      screenHeight * maxHeightFraction,
    );

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        controller.updateViewInsets(viewInsetsBottom);
        final panel = controller.activePanel;
        if (panel == ComposerPanel.none) {
          final placeholderHeight = controller.currentReservedHeight(
            viewInsetsBottom: viewInsetsBottom,
            maxAvailableHeight: maxAvailableHeight,
          );
          if (placeholderHeight <= 0) {
            return const SizedBox.shrink();
          }
          return SizedBox(height: placeholderHeight);
        }

        if (panel == ComposerPanel.attachment) {
          final cs = Theme.of(context).colorScheme;
          return Material(
            color: cs.surface,
            child: SafeArea(top: false, child: attachmentBuilder(context)),
          );
        }

        final height = controller.currentReservedHeight(
          viewInsetsBottom: viewInsetsBottom,
          maxAvailableHeight: maxAvailableHeight,
        );
        if (height <= 0) {
          return const SizedBox.shrink();
        }
        return SizedBox(
          height: height,
          child: emojiBuilder(context, height),
        );
      },
    );
  }
}
