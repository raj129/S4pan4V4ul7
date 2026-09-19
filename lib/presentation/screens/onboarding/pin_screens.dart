import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/services/pin_validator.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../../domain/entities/user_mode.dart';
import '../../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../../presentation/state/onboarding/onboarding_state.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/pin/pin_pad.dart';

/// Screen 4: Create PIN screen.
///
/// 4-digit app PIN entry. Shows dot indicators only — digits are never
/// displayed as text. PIN value is sent to the cubit and immediately
/// discarded from widget state.
class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({required this.mode, super.key});
  final UserMode mode;

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  static const int _pinLength = PinValidator.requiredLength;
  final _digits = <int>[];

  void _onDigitTap(int digit) {
    if (_digits.length >= _pinLength) return;
    setState(() => _digits.add(digit));
    context.read<OnboardingCubit>().pinDigitChanged(
      widget.mode,
      _digits.length,
    );
    if (_digits.length == _pinLength) {
      _submit();
    }
  }

  void _onDelete() {
    if (_digits.isEmpty) return;
    setState(() => _digits.removeLast());
    context.read<OnboardingCubit>().pinDigitChanged(
      widget.mode,
      _digits.length,
    );
  }

  void _submit() {
    final pin = _digits.join();
    // Clear digits from widget state before passing to cubit.
    setState(() => _digits.clear());
    context.read<OnboardingCubit>().pinEntered(widget.mode, pin);
  }

  @override
  void dispose() {
    // Ensure digits are not retained after navigation.
    _digits.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create PIN')),
      body: BlocBuilder<OnboardingCubit, OnboardingState>(
        builder: (context, state) {
          final String? errorMsg = state is OnboardingPinInvalid
              ? state.message
              : null;
          // If invalid, reset digits so user re-enters from scratch.
          if (state is OnboardingPinInvalid && _digits.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(_digits.clear);
            });
          }
          return _PinEntryLayout(
            icon: Icons.lock_outline_rounded,
            title: 'Create your vault PIN',
            subtitle: 'This PIN is separate from your device PIN.',
            filledCount: _digits.length,
            total: _pinLength,
            errorMessage: errorMsg,
            onDigit: _onDigitTap,
            onDelete: _onDelete,
          );
        },
      ),
    );
  }
}

/// Screen 5: Confirm PIN screen (re-enter to verify match).
class ConfirmPinScreen extends StatefulWidget {
  const ConfirmPinScreen({required this.mode, super.key});
  final UserMode mode;

  @override
  State<ConfirmPinScreen> createState() => _ConfirmPinScreenState();
}

class _ConfirmPinScreenState extends State<ConfirmPinScreen> {
  static const int _pinLength = PinValidator.requiredLength;
  final _digits = <int>[];

  void _onDigitTap(int digit) {
    if (_digits.length >= _pinLength) return;
    setState(() => _digits.add(digit));
    context.read<OnboardingCubit>().pinConfirmDigitChanged(
      widget.mode,
      _digits.length,
    );
    if (_digits.length == _pinLength) {
      _submit();
    }
  }

  void _onDelete() {
    if (_digits.isEmpty) return;
    setState(() => _digits.removeLast());
    context.read<OnboardingCubit>().pinConfirmDigitChanged(
      widget.mode,
      _digits.length,
    );
  }

  void _submit() {
    final pin = _digits.join();
    setState(() => _digits.clear());
    context.read<OnboardingCubit>().pinConfirmed(widget.mode, pin);
  }

  @override
  void dispose() {
    _digits.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm PIN')),
      body: BlocBuilder<OnboardingCubit, OnboardingState>(
        builder: (context, state) {
          final String? errorMsg = state is OnboardingPinInvalid
              ? state.message
              : null;
          if (state is OnboardingPinInvalid && _digits.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(_digits.clear);
            });
          }
          return _PinEntryLayout(
            icon: Icons.verified_user_outlined,
            title: 'Confirm your vault PIN',
            subtitle: 'Enter the same 4-digit PIN again.',
            filledCount: _digits.length,
            total: _pinLength,
            errorMessage: errorMsg,
            onDigit: _onDigitTap,
            onDelete: _onDelete,
          );
        },
      ),
    );
  }
}

class _PinEntryLayout extends StatelessWidget {
  const _PinEntryLayout({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.filledCount,
    required this.total,
    required this.onDigit,
    required this.onDelete,
    this.errorMessage,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int filledCount;
  final int total;
  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: AppSpacing.page,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: AppSpacing.xxl),
            _PinHero(icon: icon, title: title, subtitle: subtitle),
            const SizedBox(height: AppSpacing.xxl),
            PinDotRow(
              filledCount: filledCount,
              total: total,
              hasError: errorMessage != null,
            ),
            AnimatedSwitcher(
              duration: AppDuration.fast,
              child: errorMessage == null
                  ? const SizedBox(height: AppSpacing.xl)
                  : Padding(
                      key: ValueKey(errorMessage),
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: InfoBanner(
                        message: errorMessage!,
                        tone: InfoBannerTone.error,
                      ),
                    ),
            ),
            const Spacer(),
            PinPad(onDigit: onDigit, onDelete: onDelete),
            Text(
              'Digits are hidden and never shown on screen.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _PinHero extends StatelessWidget {
  const _PinHero({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primaryContainer,
          ),
          child: Icon(
            icon,
            size: AppSpacing.xxl,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
