import 'package:flutter/material.dart';

/// Colours and metrics for the calculator surface.
///
/// Values match the dark palette already used by `UtilityShell` so the
/// calculator blends into the surrounding shell.
class CalculatorTheme {
  const CalculatorTheme._();

  static const Color surface = Color(0xFF171B25);
  static const Color keyBackground = Color(0xFF232938);
  static const Color keyMuted = Color(0xFF1E2431);
  static const Color accent = Color(0xFF4B6BFB);
  static const Color accentPressed = Color(0xFF6B8BFF);
  static const Color destructive = Color(0xFFE0574B);
  static const Color primaryText = Colors.white;
  static const Color secondaryText = Colors.white70;
  static const Color mutedText = Colors.white38;

  static const double keyRadius = 18;
  static const double panelRadius = 28;
  static const double keySpacing = 8;

  static const List<BoxShadow> panelShadow = <BoxShadow>[
    BoxShadow(blurRadius: 22, offset: Offset(0, 16), color: Color(0x33000000)),
  ];
}
