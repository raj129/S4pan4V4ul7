import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/presentation/theme/app_colors.dart';
import 'package:photo_vault/core/presentation/theme/chat_theme.dart';

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('read ticks maintain icon contrast across palettes and brightness', () {
    for (final palette in AppThemePalette.values) {
      for (final brightness in Brightness.values) {
        final chat = ChatColors.of(brightness, palette: palette);
        expect(
          _contrastRatio(chat.readTick, chat.bubbleMine),
          greaterThanOrEqualTo(3),
          reason: '${palette.id} in $brightness',
        );
      }
    }
  });
}
