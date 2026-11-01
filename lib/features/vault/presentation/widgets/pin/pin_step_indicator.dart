import 'package:flutter/material.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';

/// "Step X of Y" label plus a segmented progress bar for multi-step PIN flows.
///
/// Makes it obvious that a second or third PIN entry is a new step (confirm,
/// new PIN, ...) rather than the previous entry having failed.
class PinStepIndicator extends StatelessWidget {
  const PinStepIndicator({
    required this.current,
    required this.total,
    super.key,
  }) : assert(current >= 1 && current <= total);

  /// 1-based index of the active step.
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Step $current of $total',
      excludeSemantics: true,
      child: Column(
        children: [
          Text(
            'Step $current of $total',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= total; i++)
                AnimatedContainer(
                  duration: AppDuration.fast,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == current ? 28 : 14,
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: i <= current
                        ? scheme.primary
                        : scheme.outlineVariant,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
