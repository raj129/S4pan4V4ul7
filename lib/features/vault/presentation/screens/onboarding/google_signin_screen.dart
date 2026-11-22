import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:photo_vault/core/widgets/app_surfaces.dart';
import '../../state/onboarding_cubit.dart';
import '../../state/onboarding_state.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'onboarding_wizard_header.dart';

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
      body: BlocBuilder<OnboardingCubit, OnboardingState>(
        builder: (context, state) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  OnboardingWizardHeader(
                    currentStep: 1,
                    onBack: () =>
                        context.read<OnboardingCubit>().fallbackToLocalMode(),
                  ),
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
                            'Sign in with Gmail',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineSmall,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            'Required for Secure Chat and encrypted Google Drive backup & restore. After signing in, you will create your PIN and restore any existing backups.',
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
                      message: 'Signed in with Google',
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
