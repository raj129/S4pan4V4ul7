import 'package:flutter/material.dart';

import '../theme/calculator_theme.dart';

/// Enum for layout mode based on aspect ratio
enum CalculatorLayoutMode {
  /// Portrait/tall screen: calculator sticks to bottom
  portraitStickBottom,

  /// Landscape/wide screen: calculator expands to fill
  landscapeExpand,
}

/// Responsive layout helper for the calculator.
///
/// Provides aspect-ratio detection, layout mode determination, and responsive sizing.
class CalculatorResponsive {
  static const double _landscapeAspectThreshold = 1.1;

  /// Determines layout mode based on screen size.
  ///
  /// - aspect < 1.1: portrait (bottom-stick)
  /// - aspect >= 1.1: landscape (expand)
  static CalculatorLayoutMode getLayoutMode(BoxConstraints constraints) {
    if (constraints.maxHeight == double.infinity) {
      return CalculatorLayoutMode.portraitStickBottom;
    }
    final aspectRatio = constraints.maxWidth / constraints.maxHeight;
    if (aspectRatio >= _landscapeAspectThreshold) {
      return CalculatorLayoutMode.landscapeExpand;
    }
    return CalculatorLayoutMode.portraitStickBottom;
  }

  /// Determines if the screen is compact (small height).
  static bool isCompact(BoxConstraints constraints) =>
      constraints.maxHeight < 560;

  /// Calculates basic keypad row height based on layout mode and constraints.
  ///
  /// Portrait: tighter spacing, keys clamped 48-76 pt
  /// Landscape: keys can grow to 72-96 pt for easier tapping
  static double calculateKeyHeight(
    BoxConstraints constraints,
    bool scientificExpanded,
  ) {
    const rows = 5;
    final layoutMode = getLayoutMode(constraints);
    final scientificHeight = scientificExpanded ? 3 * 52.0 : 0.0;

    // Subtract display, memory bar, and scientific rows
    final fixedHeight =
        190.0 + scientificHeight + CalculatorTheme.keySpacing * rows;
    final available = constraints.maxHeight - fixedHeight;
    final perRow = (available / rows).isFinite ? available / rows : 60.0;

    if (layoutMode == CalculatorLayoutMode.portraitStickBottom) {
      return perRow.clamp(48.0, 76.0);
    } else {
      return perRow.clamp(60.0, 96.0);
    }
  }

  /// Padding for the calculator content in each layout mode.
  static EdgeInsets contentPadding(CalculatorLayoutMode mode) {
    switch (mode) {
      case CalculatorLayoutMode.portraitStickBottom:
        return const EdgeInsets.only(bottom: 8);
      case CalculatorLayoutMode.landscapeExpand:
        return const EdgeInsets.all(8);
    }
  }

  /// Spacing between display, memory bar, and keypad in each layout mode.
  static double sectionSpacing(CalculatorLayoutMode mode, bool compact) {
    if (mode == CalculatorLayoutMode.portraitStickBottom) {
      return compact ? 6.0 : 10.0;
    } else {
      return compact ? 4.0 : 8.0;
    }
  }
}
