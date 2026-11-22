import 'package:flutter/material.dart';

import '../presentation/theme/app_colors.dart';
import '../presentation/theme/app_spacing.dart';

/// Small label introducing a group of rows in Android 17 / Material 3 style.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.label, {super.key, this.padding, this.trailing});

  final String label;
  final EdgeInsetsGeometry? padding;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding:
          padding ??
          const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Tonal circular icon badge used on Android 17 / Material 3 Expressive
/// settings rows.
class SettingsIconBadge extends StatelessWidget {
  const SettingsIconBadge({
    super.key,
    required this.icon,
    this.backgroundColor,
    this.iconColor,
    this.size = 40,
  });

  final IconData icon;
  final Color? backgroundColor;
  final Color? iconColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor ?? cs.primaryContainer,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        size: size * 0.52,
        color: iconColor ?? cs.onPrimaryContainer,
      ),
    );
  }
}

/// Rounded container that groups related rows into one visual block
/// (Android 17 / Material 3 Expressive style).
class SettingsCard extends StatelessWidget {
  const SettingsCard({
    super.key,
    required this.children,
    this.margin,
    this.dividers = true,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  /// Insert hairline dividers between children.
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visibleChildren = children
        .where((c) => c is! SizedBox || (c.width != 0 && c.height != 0))
        .toList(growable: false);
    final items = <Widget>[];
    for (var i = 0; i < visibleChildren.length; i++) {
      items.add(visibleChildren[i]);
      if (dividers && i != visibleChildren.length - 1) {
        items.add(
          Divider(
            height: 1,
            indent: AppSpacing.lg,
            endIndent: AppSpacing.lg,
            color: cs.outlineVariant.withValues(alpha: 0.35),
          ),
        );
      }
    }

    return Padding(
      padding: margin ?? const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Material(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: items),
      ),
    );
  }
}

/// Tone of an [InfoBanner].
enum InfoBannerTone { info, success, warning, error }

/// Inline banner used for success/error/warning messaging.
///
/// Replaces the duplicated private `_SuccessBanner` / `_ErrorBanner` pairs.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.message,
    this.tone = InfoBannerTone.info,
    this.title,
    this.icon,
    this.action,
  });

  final String message;
  final InfoBannerTone tone;
  final String? title;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semantic;
    final (accent, fallbackIcon) = switch (tone) {
      InfoBannerTone.info => (
        theme.colorScheme.primary,
        Icons.info_outline_rounded,
      ),
      InfoBannerTone.success => (
        semantic.success,
        Icons.check_circle_outline_rounded,
      ),
      InfoBannerTone.warning => (semantic.warning, Icons.warning_amber_rounded),
      InfoBannerTone.error => (
        theme.colorScheme.error,
        Icons.error_outline_rounded,
      ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.10),
        borderRadius: AppRadius.all(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? fallbackIcon, size: 20, color: accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.titleSmall?.copyWith(color: accent),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(message, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Shared photo/video grid used by gallery, trash and import review, so the
/// three no longer hand-roll the same `GridView` geometry.
class MediaGrid extends StatelessWidget {
  const MediaGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.controller,
    this.padding,
    this.maxTileExtent = 132,
    this.spacing = AppSpacing.xs,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry? padding;
  final double maxTileExtent;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      controller: controller,
      padding: padding ?? const EdgeInsets.all(AppSpacing.sm),
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxTileExtent,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: itemCount,
      itemBuilder: itemBuilder,
    );
  }
}
