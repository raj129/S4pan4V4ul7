import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Inter-based type scale for the whole app.
///
/// Sizes are tightened slightly from the Material defaults: this is a dense,
/// list-and-chat heavy app, and the stock scale leaves rows looking airy and
/// inconsistent next to one another.
abstract final class AppTypography {
  static TextTheme textTheme(Brightness brightness) {
    final base = brightness == Brightness.dark
        ? Typography.material2021().white
        : Typography.material2021().black;

    return GoogleFonts.interTextTheme(base).copyWith(
      displaySmall: GoogleFonts.inter(
        textStyle: base.displaySmall,
        fontSize: 34,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.6,
      ),
      headlineMedium: GoogleFonts.inter(
        textStyle: base.headlineMedium,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
      headlineSmall: GoogleFonts.inter(
        textStyle: base.headlineSmall,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: GoogleFonts.inter(
        textStyle: base.titleLarge,
        fontSize: 19,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: GoogleFonts.inter(
        textStyle: base.titleMedium,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
      ),
      titleSmall: GoogleFonts.inter(
        textStyle: base.titleSmall,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: GoogleFonts.inter(
        textStyle: base.bodyLarge,
        fontSize: 15.5,
        height: 1.35,
      ),
      bodyMedium: GoogleFonts.inter(
        textStyle: base.bodyMedium,
        fontSize: 14,
        height: 1.35,
      ),
      bodySmall: GoogleFonts.inter(
        textStyle: base.bodySmall,
        fontSize: 12.5,
        height: 1.3,
      ),
      labelLarge: GoogleFonts.inter(
        textStyle: base.labelLarge,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      ),
      labelMedium: GoogleFonts.inter(
        textStyle: base.labelMedium,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      labelSmall: GoogleFonts.inter(
        textStyle: base.labelSmall,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.2,
      ),
    );
  }

  /// Uppercase micro-label used for section headers and day dividers.
  static TextStyle overline(Color color) => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.8,
    color: color,
  );

  /// Timestamp / delivery-tick row inside a chat bubble.
  static TextStyle bubbleMeta(Color color) =>
      GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: color);
}
