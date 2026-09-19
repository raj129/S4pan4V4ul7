import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_surfaces.dart';
import '../../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../../presentation/state/onboarding/onboarding_state.dart';
import '../../theme/app_spacing.dart';

/// Screen 3 (optional): Google sign-in.
///
/// Only shown when the user tapped "Sign in with Google" on the welcome screen.
/// On failure, clearly offers "Continue locally" as an escape hatch.
class GoogleSignInScreen extends StatelessWidget {
  const GoogleSignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                              Icons.backup_rounded,
                              size: AppSpacing.huge,
                              color: theme.colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          Text(
                            'Enable encrypted backup & restore',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Your vault key is encrypted before backup. Google cannot read your photos or keys.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (state is OnboardingGoogleSignInFailed) ...[
                    InfoBanner(
                      message: state.message,
                      tone: InfoBannerTone.error,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (state is OnboardingGoogleSignInSuccess) ...[
                    InfoBanner(
                      message: 'Signed in as ${state.email}',
                      tone: InfoBannerTone.success,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton.icon(
                      onPressed: () => context.push('/restore'),
                      icon: const Icon(Icons.restore_rounded),
                      label: const Text('Restore from Google backup'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton.icon(
                      onPressed: () => context
                          .read<OnboardingCubit>()
                          .continueGoogleAsNewVault(),
                      icon: const Icon(Icons.vpn_key_outlined),
                      label: const Text('Create new vault instead'),
                    ),
                  ] else if (state is OnboardingGoogleSignInInProgress)
                    const Center(child: CircularProgressIndicator())
                  else
                    FilledButton.icon(
                      onPressed: () =>
                          context.read<OnboardingCubit>().selectGoogleMode(),
                      icon: const Icon(Icons.account_circle_outlined),
                      label: const Text('Continue with Google'),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: () =>
                        context.read<OnboardingCubit>().fallbackToLocalMode(),
                    child: const Text('Skip — continue locally instead'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
