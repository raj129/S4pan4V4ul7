import 'package:flutter/material.dart';

import '../../../core/widgets/app_surfaces.dart';
import '../../theme/app_spacing.dart';

/// Bottom sheet explaining local vs Google mode.
/// No actions — purely informational.
class ModeInfoSheet extends StatelessWidget {
  const ModeInfoSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.lg,
        AppSpacing.xl,
        AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: AppSpacing.huge,
              height: AppSpacing.xs,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: AppRadius.all(AppRadius.pill),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('Local vs Google mode', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.xl),
          const _ModeRow(
            icon: Icons.smartphone_rounded,
            title: 'Continue locally',
            description:
                'Photos stay encrypted on this device only. If you lose this device, the vault cannot be restored.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const _ModeRow(
            icon: Icons.backup_rounded,
            title: 'Sign in with Google',
            description:
                'Enables encrypted VMK backup and optional photo sync. You can restore on a new device after signing in.',
          ),
          const SizedBox(height: AppSpacing.lg),
          const InfoBanner(
            message: 'You can enable Google backup at any time from settings.',
            tone: InfoBannerTone.info,
          ),
        ],
      ),
    );
  }
}

class _ModeRow extends StatelessWidget {
  const _ModeRow({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: AppRadius.all(AppRadius.sm),
          ),
          child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
