import 'package:flutter/material.dart';

import '../../presentation/theme/app_colors.dart';
import '../../presentation/theme/app_spacing.dart';
import '../../presentation/theme/app_typography.dart';

/// Small uppercase label introducing a group of rows.
///
/// Centralises the private `_SectionHeader` copies that previously lived in
/// individual screens.
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
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.sm,
          ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: AppTypography.overline(theme.colorScheme.primary),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Rounded container that groups related rows into one visual block.
///
/// Rows inside are separated by inset dividers rather than each row carrying
/// its own border, which keeps settings-style lists calm.
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
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (dividers && i != children.length - 1) {
        items.add(
          const Divider(height: 1, indent: AppSpacing.lg, endIndent: AppSpacing.lg),
        );
      }
    }

    return Padding(
      padding:
          margin ??
          const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Card(child: Column(mainAxisSize: MainAxisSize.min, children: items)),
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
          if (action != null) ...[const SizedBox(width: AppSpacing.sm), action!],
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
