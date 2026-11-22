import 'package:flutter/material.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';

/// Compact Material 3 wizard header for the 4-step onboarding flow:
/// 1. Google Sign-In
/// 2. Create PIN
/// 3. Confirm PIN
/// 4. Restore & Setup
class OnboardingWizardHeader extends StatelessWidget {
  const OnboardingWizardHeader({
    required this.currentStep,
    this.stepLabel,
    this.onBack,
    super.key,
  }) : assert(currentStep >= 1 && currentStep <= totalSteps);

  static const int totalSteps = 4;

  static const List<String> _defaultLabels = [
    'Google Sign-In',
    'Create PIN',
    'Confirm PIN',
    'Restore & Setup',
  ];

  /// 1-based step index (1..4).
  final int currentStep;
  final String? stepLabel;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = stepLabel ?? _defaultLabels[currentStep - 1];

    return Semantics(
      label: 'Step $currentStep of $totalSteps: $label',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (onBack != null) ...[
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: 'Back',
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Step $currentStep of $totalSteps',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: '  ·  $label',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: currentStep / totalSteps,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
        ],
      ),
    );
  }
}
