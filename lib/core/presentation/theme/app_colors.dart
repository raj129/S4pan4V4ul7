import 'package:flutter/material.dart';

/// Curated Material 3 theme color palettes selectable in Settings.
enum AppThemePalette {
  royalIndigo(
    id: 'indigo',
    label: 'Royal Indigo',
    seed: Color(0xFF4F46E5),
    bubbleMineLight: Color(0xFFE0E7FF),
    onBubbleMineLight: Color(0xFF1E1B4B),
    bubbleMineDark: Color(0xFF282566),
    onBubbleMineDark: Color(0xFFEEF2FF),
    readTick: Color(0xFF6366F1),
  ),
  oceanBlue(
    id: 'ocean',
    label: 'Ocean Blue',
    seed: Color(0xFF0284C7),
    bubbleMineLight: Color(0xFFE0F2FE),
    onBubbleMineLight: Color(0xFF0C4A6E),
    bubbleMineDark: Color(0xFF0C3B5E),
    onBubbleMineDark: Color(0xFFF0F9FF),
    readTick: Color(0xFF38BDF8),
  ),
  amethystViolet(
    id: 'violet',
    label: 'Amethyst',
    seed: Color(0xFF7C3AED),
    bubbleMineLight: Color(0xFFEDE9FE),
    onBubbleMineLight: Color(0xFF2E1065),
    bubbleMineDark: Color(0xFF3B1D7A),
    onBubbleMineDark: Color(0xFFF5F3FF),
    readTick: Color(0xFFA78BFA),
  ),
  emeraldTeal(
    id: 'emerald',
    label: 'Emerald',
    seed: Color(0xFF0D9488),
    bubbleMineLight: Color(0xFFCCFBF1),
    onBubbleMineLight: Color(0xFF134E4A),
    bubbleMineDark: Color(0xFF11423E),
    onBubbleMineDark: Color(0xFFF0FDFA),
    readTick: Color(0xFF2DD4BF),
  ),
  roseCrimson(
    id: 'rose',
    label: 'Crimson Rose',
    seed: Color(0xFFE11D48),
    bubbleMineLight: Color(0xFFFFE4E6),
    onBubbleMineLight: Color(0xFF4C0519),
    bubbleMineDark: Color(0xFF571327),
    onBubbleMineDark: Color(0xFFFFF1F2),
    readTick: Color(0xFFFB7185),
  ),
  amberGold(
    id: 'amber',
    label: 'Amber Gold',
    seed: Color(0xFFD97706),
    bubbleMineLight: Color(0xFFFEF3C7),
    onBubbleMineLight: Color(0xFF451A03),
    bubbleMineDark: Color(0xFF542D09),
    onBubbleMineDark: Color(0xFFFFFBEB),
    readTick: Color(0xFFFBBF24),
  );

  const AppThemePalette({
    required this.id,
    required this.label,
    required this.seed,
    required this.bubbleMineLight,
    required this.onBubbleMineLight,
    required this.bubbleMineDark,
    required this.onBubbleMineDark,
    required this.readTick,
  });

  final String id;
  final String label;
  final Color seed;
  final Color bubbleMineLight;
  final Color onBubbleMineLight;
  final Color bubbleMineDark;
  final Color onBubbleMineDark;
  final Color readTick;

  static AppThemePalette fromId(String? id) {
    if (id == null) return AppThemePalette.royalIndigo;
    for (final palette in AppThemePalette.values) {
      if (palette.id == id) return palette;
    }
    return AppThemePalette.royalIndigo;
  }
}

/// Brand and semantic colour tokens.
///
/// Semantic colours live here rather than being spelled `Colors.green` at the
/// call site so that both brightnesses stay legible and a palette change is a
/// one-file edit.
abstract final class AppColors {
  /// Default seed for the Material 3 tonal palettes (Royal Indigo).
  static const seed = Color(0xFF4F46E5);

  // -- Presence -------------------------------------------------------------
  static const onlineLight = Color(0xFF10B981);
  static const onlineDark = Color(0xFF34D399);
  static const awayLight = Color(0xFFD97706);
  static const awayDark = Color(0xFFFBBF24);
  static const offlineLight = Color(0xFF818A95);
  static const offlineDark = Color(0xFF68707A);

  // -- Status ---------------------------------------------------------------
  static const successLight = Color(0xFF059669);
  static const successDark = Color(0xFF34D399);
  static const warningLight = Color(0xFFB45309);
  static const warningDark = Color(0xFFFBBF24);
  static const dangerLight = Color(0xFFD51928);
  static const dangerDark = Color(0xFFFF5B61);

  // -- Chat (Default Royal Indigo Tonal Palette) ----------------------------
  static const readTick = Color(0xFF6366F1);

  static const bubbleMineLight = Color(0xFFE0E7FF);
  static const bubbleMineDark = Color(0xFF282566);
  static const onBubbleMineLight = Color(0xFF1E1B4B);
  static const onBubbleMineDark = Color(0xFFEEF2FF);

  static const bubbleTheirsLight = Color(0xFFF1F5F9);
  static const bubbleTheirsDark = Color(0xFF1E2430);
  static const onBubbleTheirsLight = Color(0xFF0F172A);
  static const onBubbleTheirsDark = Color(0xFFF1F5F9);

  static const wallpaperLight = Color(0xFFF8FAFC);
  static const wallpaperDark = Color(0xFF0D1117);
  static const wallpaperPatternLight = Color(0xFF64748B);
  static const wallpaperPatternDark = Color(0xFF94A3B8);
}

/// Semantic colours resolved for the active brightness.
///
/// Exposed as a [ThemeExtension] so widgets read tokens from the theme instead
/// of branching on [Brightness] themselves.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.online,
    required this.away,
    required this.offline,
    required this.success,
    required this.warning,
    required this.danger,
  });

  factory AppSemanticColors.of(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return AppSemanticColors(
      online: dark ? AppColors.onlineDark : AppColors.onlineLight,
      away: dark ? AppColors.awayDark : AppColors.awayLight,
      offline: dark ? AppColors.offlineDark : AppColors.offlineLight,
      success: dark ? AppColors.successDark : AppColors.successLight,
      warning: dark ? AppColors.warningDark : AppColors.warningLight,
      danger: dark ? AppColors.dangerDark : AppColors.dangerLight,
    );
  }

  final Color online;
  final Color away;
  final Color offline;
  final Color success;
  final Color warning;
  final Color danger;

  @override
  AppSemanticColors copyWith({
    Color? online,
    Color? away,
    Color? offline,
    Color? success,
    Color? warning,
    Color? danger,
  }) {
    return AppSemanticColors(
      online: online ?? this.online,
      away: away ?? this.away,
      offline: offline ?? this.offline,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
    );
  }

  @override
  AppSemanticColors lerp(AppSemanticColors? other, double t) {
    if (other == null) return this;
    return AppSemanticColors(
      online: Color.lerp(online, other.online, t)!,
      away: Color.lerp(away, other.away, t)!,
      offline: Color.lerp(offline, other.offline, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
    );
  }
}

/// `context.semantic` access to the resolved semantic palette.
extension AppSemanticColorsX on BuildContext {
  AppSemanticColors get semantic =>
      Theme.of(this).extension<AppSemanticColors>() ??
      AppSemanticColors.of(Theme.of(this).brightness);
}
