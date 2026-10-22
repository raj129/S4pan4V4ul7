import 'package:flutter/material.dart';

/// Brand and semantic colour tokens.
///
/// Semantic colours live here rather than being spelled `Colors.green` at the
/// call site so that both brightnesses stay legible and a palette change is a
/// one-file edit.
abstract final class AppColors {
  /// Seed for the Material 3 tonal palettes.
  static const seed = Color(0xFF4A6CF7);

  // -- Presence -------------------------------------------------------------
  static const onlineLight = Color(0xFF1FA463);
  static const onlineDark = Color(0xFF4ADE80);
  static const awayLight = Color(0xFFCC8A00);
  static const awayDark = Color(0xFFFBBF24);
  static const offlineLight = Color(0xFF8A9099);
  static const offlineDark = Color(0xFF6B7280);

  // -- Status ---------------------------------------------------------------
  static const successLight = Color(0xFF1B8A55);
  static const successDark = Color(0xFF34D399);
  static const warningLight = Color(0xFFB45309);
  static const warningDark = Color(0xFFFBBF24);
  static const dangerLight = Color(0xFFD32F2F);
  static const dangerDark = Color(0xFFF87171);

  // -- Chat -----------------------------------------------------------------
  static const readTick = Color(0xFF34B7F1);

  static const bubbleMineLight = Color(0xFFD7E3FF);
  static const bubbleMineDark = Color(0xFF2B4A8B);
  static const onBubbleMineLight = Color(0xFF0D1B33);
  static const onBubbleMineDark = Color(0xFFEAF0FF);

  static const bubbleTheirsLight = Color(0xFFFFFFFF);
  static const bubbleTheirsDark = Color(0xFF232833);
  static const onBubbleTheirsLight = Color(0xFF141821);
  static const onBubbleTheirsDark = Color(0xFFE6E8EC);

  static const wallpaperLight = Color(0xFFF2F0EA);
  static const wallpaperDark = Color(0xFF0E1116);
  static const wallpaperPatternLight = Color(0xFF6B6455);
  static const wallpaperPatternDark = Color(0xFF9AA4B2);
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
