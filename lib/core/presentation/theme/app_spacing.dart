import 'package:flutter/widgets.dart';

/// Spacing scale. Every gap in the app should be one of these.
abstract final class AppSpacing {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 48;

  /// Standard horizontal page inset.
  static const EdgeInsets page = EdgeInsets.symmetric(horizontal: lg);

  /// Standard inset for a screen whose content scrolls vertically.
  static const EdgeInsets pageVertical = EdgeInsets.fromLTRB(lg, lg, lg, xxl);
}

/// Corner radii. Larger values read as "pill", smaller as "card".
abstract final class AppRadius {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;

  static const Radius bubble = Radius.circular(18);
  static const Radius bubbleTight = Radius.circular(6);

  static BorderRadius all(double value) => BorderRadius.circular(value);
}

/// Elevation is used sparingly: surfaces are mostly separated by tone, with a
/// soft shadow reserved for things that genuinely float (bubbles, composer).
abstract final class AppElevation {
  static const double none = 0;
  static const double card = 0;
  static const double raised = 2;
  static const double floating = 6;
}

/// Shared animation durations, so motion feels consistent across screens.
abstract final class AppDuration {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
}
