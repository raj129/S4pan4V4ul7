import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/user_mode.dart';
import '../../../presentation/state/onboarding/onboarding_cubit.dart';
import '../../../presentation/state/onboarding/onboarding_state.dart';
import 'pin_dot_row.dart';

/// Screen 4: Create PIN screen.
///
/// 6-digit app PIN entry. Shows dot indicators only — digits are never
/// displayed as text. PIN value is sent to the cubit and immediately
/// discarded from widget state.
class CreatePinScreen extends StatefulWidget {
  const CreatePinScreen({required this.mode, super.key});
  final UserMode mode;

  @override
  State<CreatePinScreen> createState() => _CreatePinScreenState();
}

class _CreatePinScreenState extends State<CreatePinScreen> {
  static const int _pinLength = 6;
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
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _digits.clear()),
            );
          }
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text(
                  'Create your vault PIN',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'This PIN is separate from your device PIN.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                PinDotRow(filledCount: _digits.length, total: _pinLength),
                if (errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      errorMsg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _PinPad(onDigit: _onDigitTap, onDelete: _onDelete),
                const SizedBox(height: 24),
              ],
            ),
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
  static const int _pinLength = 6;
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
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => setState(() => _digits.clear()),
            );
          }
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text(
                  'Confirm your vault PIN',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter the same 6-digit PIN again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),
                PinDotRow(filledCount: _digits.length, total: _pinLength),
                if (errorMsg != null) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      errorMsg,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _PinPad(onDigit: _onDigitTap, onDelete: _onDelete),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Shared PIN pad widget
// ─────────────────────────────────────────────

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onDelete});
  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;

  static const _layout = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
    [-1, 0, -2], // -1 = empty, -2 = delete
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: _layout.map((row) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: row.map((digit) {
              if (digit == -1) return const SizedBox(width: 72, height: 72);
              if (digit == -2) {
                return _PinKey(
                  onTap: onDelete,
                  child: const Icon(Icons.backspace_outlined),
                );
              }
              return _PinKey(
                onTap: () => onDigit(digit),
                child: Text(
                  '$digit',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              );
            }).toList(),
          );
        }).toList(),
      ),
    );
  }
}

class _PinKey extends StatelessWidget {
  const _PinKey({required this.child, required this.onTap});
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      borderRadius: BorderRadius.circular(36),
      child: SizedBox(width: 72, height: 72, child: Center(child: child)),
    );
  }
}
