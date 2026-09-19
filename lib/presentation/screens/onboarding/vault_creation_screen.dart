import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/widgets/app_state_views.dart';
import '../../../domain/entities/user_mode.dart';
import '../../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../../presentation/state/onboarding/onboarding_state.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// Screen 7: Vault creation progress screen.
///
/// Shows animated step indicators while the vault is being created.
/// On success, navigation to gallery is driven by [OnboardingVaultCreated].
class VaultCreationScreen extends StatelessWidget {
  const VaultCreationScreen({required this.mode, super.key});
  final UserMode mode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: BlocBuilder<OnboardingCubit, OnboardingState>(
        builder: (context, state) {
          if (state is OnboardingError) {
            return ErrorView(
              title: 'Vault creation failed',
              message: state.message,
              onRetry: state.canRetry
                  ? () => context.read<OnboardingCubit>().retry()
                  : null,
              retryLabel: 'Try again',
            );
          }

          final step = state is OnboardingCreatingVault
              ? state.step
              : VaultCreationStep.done;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          const SizedBox(height: AppSpacing.huge),
                          Container(
                            width: AppSpacing.huge * 2,
                            height: AppSpacing.huge * 2,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: AppRadius.all(AppRadius.xl),
                            ),
                            child: Icon(
                              Icons.enhanced_encryption_rounded,
                              size: AppSpacing.huge,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          Text(
                            'Creating your encrypted vault…',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            mode == UserMode.googleEnabled
                                ? 'Setting up local encryption and encrypted Google backup.'
                                : 'Generating keys and preparing secure local storage.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          ..._steps.map(
                            (s) => _StepRow(
                              label: s.label,
                              isDone:
                                  s.step.index < step.index ||
                                  step == VaultCreationStep.done,
                              isActive: s.step == step,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const LinearProgressIndicator(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _StepDef {
  const _StepDef(this.step, this.label);
  final VaultCreationStep step;
  final String label;
}

const _steps = [
  _StepDef(VaultCreationStep.generatingKeys, 'Generating encryption keys'),
  _StepDef(VaultCreationStep.wrappingVmk, 'Protecting vault master key'),
  _StepDef(VaultCreationStep.savingToSecureStorage, 'Saving to secure storage'),
  _StepDef(VaultCreationStep.initializingDatabase, 'Initializing vault'),
];

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.isDone,
    required this.isActive,
  });

  final String label;
  final bool isDone;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDone
        ? context.semantic.success
        : isActive
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: AppDuration.fast,
            child: Icon(
              isDone
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked,
              key: ValueKey('$label-$isDone'),
              color: color,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              label,
              style:
                  (isActive
                          ? theme.textTheme.titleSmall
                          : theme.textTheme.bodyMedium)
                      ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
