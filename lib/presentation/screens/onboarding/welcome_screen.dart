import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../../presentation/state/onboarding/onboarding_state.dart';
import 'mode_info_sheet.dart';

/// Screen 1: Welcome screen.
///
/// First thing the user sees when the user sets up the private vault.
/// Presents the vault value proposition and lets the user choose local-only
/// or Google-enabled mode with a single tap.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<OnboardingCubit, OnboardingState>(
        listener: (context, state) {
          // Navigation is handled by the router; no push needed here.
        },
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(flex: 3),
                // Logo placeholder
                const _AppLogo(),
                const SizedBox(height: 24),
                Text(
                  'Set up your private vault',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Create a passcode-protected photo vault behind the calculator.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(flex: 2),
                // Primary CTA
                FilledButton(
                  onPressed: () =>
                      context.read<OnboardingCubit>().selectLocalMode(),
                  child: const Text('Continue locally'),
                ),
                const SizedBox(height: 12),
                // Secondary CTA
                OutlinedButton.icon(
                  onPressed: () =>
                      context.read<OnboardingCubit>().selectGoogleMode(),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Sign in with Google'),
                ),
                const SizedBox(height: 16),
                // Learn more
                Center(
                  child: TextButton(
                    onPressed: () => _showModeInfo(context),
                    child: const Text('What\'s the difference?'),
                  ),
                ),
                Center(
                  child: TextButton.icon(
                    onPressed: () => context.push('/restore'),
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: const Text('Restore from Google backup'),
                  ),
                ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showModeInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const ModeInfoSheet(),
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 96,
        height: 96,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Icon(
          Icons.lock_outline_rounded,
          size: 52,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
