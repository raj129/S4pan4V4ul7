import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../../presentation/state/onboarding/onboarding_state.dart';
import '../../theme/app_spacing.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      body: BlocListener<OnboardingCubit, OnboardingState>(
        listener: (context, state) {},
        child: SafeArea(
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
                        const _AppLogo(),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(
                          'Set up your private vault',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineLarge,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        Text(
                          'Create a PIN-protected encrypted photo vault hidden behind the calculator.',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                FilledButton(
                  onPressed: () =>
                      context.read<OnboardingCubit>().selectLocalMode(),
                  child: const Text('Continue locally'),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: () =>
                      context.read<OnboardingCubit>().selectGoogleMode(),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Sign in with Google'),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(
                  onPressed: () => _showModeInfo(context),
                  child: const Text('What\'s the difference?'),
                ),
                TextButton.icon(
                  onPressed: () => context.push('/restore'),
                  icon: const Icon(Icons.restore_rounded),
                  label: const Text('Restore from Google backup'),
                ),
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
    );
  }
}

class _AppLogo extends StatelessWidget {
  const _AppLogo();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        width: AppSpacing.huge * 2,
        height: AppSpacing.huge * 2,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: AppRadius.all(AppRadius.xl),
        ),
        child: Icon(
          Icons.lock_outline_rounded,
          size: AppSpacing.huge,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
