import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/user_mode.dart';
import '../../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../../presentation/state/onboarding/onboarding_state.dart';

/// Screen 7: Vault creation progress screen.
///
/// Shows animated step indicators while the vault is being created.
/// On success, navigation to gallery is driven by [OnboardingVaultCreated].
class VaultCreationScreen extends StatelessWidget {
  const VaultCreationScreen({required this.mode, super.key});
  final UserMode mode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<OnboardingCubit, OnboardingState>(
        builder: (context, state) {
          if (state is OnboardingError) {
            return _ErrorView(
              message: state.message,
              canRetry: state.canRetry,
              onRetry: () => context.read<OnboardingCubit>().retry(),
            );
          }

          final step = state is OnboardingCreatingVault
              ? state.step
              : VaultCreationStep.done;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 32),
                  Text(
                    'Creating your encrypted vault…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 32),
                  ..._steps.map(
                    (s) => _StepRow(
                      label: s.label,
                      isDone: s.step.index < step.index,
                      isActive: s.step == step,
                    ),
                  ),
                  const Spacer(),
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
    final color = isDone
        ? Theme.of(context).colorScheme.primary
        : isActive
        ? Theme.of(context).colorScheme.secondary
        : Theme.of(context).colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isDone ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  final String message;
  final bool canRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Spacer(),
            Icon(
              Icons.error_outline_rounded,
              size: 72,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              'Vault creation failed',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (canRetry)
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
