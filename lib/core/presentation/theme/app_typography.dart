import 'package:flutter/material.dart';

/// Offline-safe type scale for the whole app.
///
/// Sizes are tightened slightly from the Material defaults: this is a dense,
/// list-and-chat heavy app, and the stock scale leaves rows looking airy and
/// inconsistent next to one another. Keeping the platform font family lets
/// Android and Windows use their bundled color emoji fallback fonts offline.
abstract final class AppTypography {
  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;

    return base.copyWith(
      displaySmall: base.displaySmall?.copyWith(
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 15.5, height: 1.35),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.35),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12.5, height: 1.3),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    );
  }

  /// Uppercase micro-label used for section headers and day dividers.
  static TextStyle overline(Color color) => TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: color,
  );

  /// Timestamp / delivery-tick row inside a chat bubble.
  static TextStyle bubbleMeta(Color color) =>
      TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color);
}
