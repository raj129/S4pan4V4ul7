import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/services/biometric_service.dart';
import '../../../domain/entities/user_mode.dart';
import '../../../presentation/state/onboarding/onboarding_cubit.dart';

/// Screen 6: Biometric setup.
///
/// Shown only when biometric hardware is available and enrolled.
/// If unavailable, the cubit skips this state automatically.
class BiometricSetupScreen extends StatelessWidget {
  const BiometricSetupScreen({
    required this.mode,
    required this.availability,
    super.key,
  });

  final UserMode mode;
  final BiometricAvailability availability;

  @override
  Widget build(BuildContext context) {
    final isAvailable = availability == BiometricAvailability.available;

    return Scaffold(
      appBar: AppBar(title: const Text('Biometric Unlock')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Icon(
                isAvailable
                    ? Icons.fingerprint_rounded
                    : Icons.fingerprint_outlined,
                size: 80,
                color: isAvailable
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(height: 24),
              Text(
                isAvailable
                    ? 'Enable biometric unlock?'
                    : 'Biometric unavailable',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                isAvailable
                    ? 'Use your fingerprint or face ID to unlock the vault quickly. '
                          'Your PIN remains the primary unlock method.'
                    : 'No biometric hardware or enrolled credentials found on this device. '
                          'You can enable it later from settings.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              if (isAvailable) ...[
                FilledButton.icon(
                  onPressed: () =>
                      context.read<OnboardingCubit>().enableBiometric(mode),
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Enable biometric unlock'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: () =>
                    context.read<OnboardingCubit>().skipBiometric(mode),
                child: Text(isAvailable ? 'Skip for now' : 'Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
