import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Chat-specific colours, kept out of [ColorScheme] because bubbles, ticks and
/// the wallpaper have no sensible Material role to map onto.
@immutable
class ChatColors extends ThemeExtension<ChatColors> {
  const ChatColors({
    required this.bubbleMine,
    required this.onBubbleMine,
    required this.bubbleTheirs,
    required this.onBubbleTheirs,
    required this.readTick,
    required this.wallpaper,
    required this.wallpaperPattern,
    required this.quoteStrip,
    required this.bubbleShadow,
  });

  factory ChatColors.of(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return ChatColors(
      bubbleMine: dark ? AppColors.bubbleMineDark : AppColors.bubbleMineLight,
      onBubbleMine: dark
          ? AppColors.onBubbleMineDark
          : AppColors.onBubbleMineLight,
      bubbleTheirs: dark
          ? AppColors.bubbleTheirsDark
          : AppColors.bubbleTheirsLight,
      onBubbleTheirs: dark
          ? AppColors.onBubbleTheirsDark
          : AppColors.onBubbleTheirsLight,
      readTick: AppColors.readTick,
      wallpaper: dark ? AppColors.wallpaperDark : AppColors.wallpaperLight,
      wallpaperPattern: dark
          ? AppColors.wallpaperPatternDark
          : AppColors.wallpaperPatternLight,
      quoteStrip: dark ? AppColors.onlineDark : AppColors.seed,
      bubbleShadow: dark
          ? Colors.black.withValues(alpha: 0.35)
          : Colors.black.withValues(alpha: 0.08),
    );
  }

  final Color bubbleMine;
  final Color onBubbleMine;
  final Color bubbleTheirs;
  final Color onBubbleTheirs;

  /// Blue double-tick shown once the recipient has read the message.
  final Color readTick;

  final Color wallpaper;
  final Color wallpaperPattern;

  /// Accent bar down the side of a quoted message.
  final Color quoteStrip;

  final Color bubbleShadow;

  Color bubbleFor({required bool isMine}) =>
      isMine ? bubbleMine : bubbleTheirs;

  Color onBubbleFor({required bool isMine}) =>
      isMine ? onBubbleMine : onBubbleTheirs;

  @override
  ChatColors copyWith({
    Color? bubbleMine,
    Color? onBubbleMine,
    Color? bubbleTheirs,
    Color? onBubbleTheirs,
    Color? readTick,
    Color? wallpaper,
    Color? wallpaperPattern,
    Color? quoteStrip,
    Color? bubbleShadow,
  }) {
    return ChatColors(
      bubbleMine: bubbleMine ?? this.bubbleMine,
      onBubbleMine: onBubbleMine ?? this.onBubbleMine,
      bubbleTheirs: bubbleTheirs ?? this.bubbleTheirs,
      onBubbleTheirs: onBubbleTheirs ?? this.onBubbleTheirs,
      readTick: readTick ?? this.readTick,
      wallpaper: wallpaper ?? this.wallpaper,
      wallpaperPattern: wallpaperPattern ?? this.wallpaperPattern,
      quoteStrip: quoteStrip ?? this.quoteStrip,
      bubbleShadow: bubbleShadow ?? this.bubbleShadow,
    );
  }

  @override
  ChatColors lerp(ChatColors? other, double t) {
    if (other == null) return this;
    return ChatColors(
      bubbleMine: Color.lerp(bubbleMine, other.bubbleMine, t)!,
      onBubbleMine: Color.lerp(onBubbleMine, other.onBubbleMine, t)!,
      bubbleTheirs: Color.lerp(bubbleTheirs, other.bubbleTheirs, t)!,
      onBubbleTheirs: Color.lerp(onBubbleTheirs, other.onBubbleTheirs, t)!,
      readTick: Color.lerp(readTick, other.readTick, t)!,
      wallpaper: Color.lerp(wallpaper, other.wallpaper, t)!,
      wallpaperPattern: Color.lerp(
        wallpaperPattern,
        other.wallpaperPattern,
        t,
      )!,
      quoteStrip: Color.lerp(quoteStrip, other.quoteStrip, t)!,
      bubbleShadow: Color.lerp(bubbleShadow, other.bubbleShadow, t)!,
    );
  }
}

/// `context.chatColors` access to the resolved chat palette.
extension ChatColorsX on BuildContext {
  ChatColors get chatColors =>
      Theme.of(this).extension<ChatColors>() ??
      ChatColors.of(Theme.of(this).brightness);
}
