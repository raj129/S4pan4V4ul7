import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../../presentation/state/onboarding/onboarding_state.dart';

/// Screen 3 (optional): Google sign-in.
///
/// Only shown when the user tapped "Sign in with Google" on the welcome screen.
/// On failure, clearly offers "Continue locally" as an escape hatch.
class GoogleSignInScreen extends StatelessWidget {
  const GoogleSignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in with Google'),
        leading: BackButton(
          onPressed: () =>
              context.read<OnboardingCubit>().fallbackToLocalMode(),
        ),
      ),
      body: BlocBuilder<OnboardingCubit, OnboardingState>(
        builder: (context, state) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(),
                  const Icon(Icons.backup_rounded, size: 72),
                  const SizedBox(height: 24),
                  Text(
                    'Enable encrypted backup & restore',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your vault key will be encrypted before being backed up. '
                    'Google cannot read your photos or keys.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  if (state is OnboardingGoogleSignInFailed)
                    _ErrorBanner(message: state.message),
                  const SizedBox(height: 12),
                  if (state is OnboardingGoogleSignInInProgress)
                    const Center(child: CircularProgressIndicator())
                  else
                    FilledButton.icon(
                      onPressed: () =>
                          context.read<OnboardingCubit>().selectGoogleMode(),
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Continue with Google'),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () =>
                        context.read<OnboardingCubit>().fallbackToLocalMode(),
                    child: const Text('Skip — continue locally instead'),
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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Theme.of(context).colorScheme.onErrorContainer,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
