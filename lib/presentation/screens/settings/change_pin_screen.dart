import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../application/services/pin_validator.dart';
import '../../../application/usecases/change_pin_usecase.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/pin/pin_pad.dart';

enum ChangePinStep { verifyOld, enterNew, confirmNew }

class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({
    required this.changePinUseCase,
    required this.pinValidator,
    this.onPinChanged,
    super.key,
  });

  final ChangePinUseCase changePinUseCase;
  final PinValidator pinValidator;

  /// Invoked with the new PIN after a successful change.
  ///
  /// Used to re-wrap the chat identity key under the new PIN. Without this the
  /// key would still be wrapped under the old PIN, and restoring chat history
  /// on another device would fail.
  final Future<void> Function(String newPin)? onPinChanged;

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  static const int _pinLength = PinValidator.requiredLength;
  final _digits = <int>[];
  ChangePinStep _step = ChangePinStep.verifyOld;
  String _oldPin = '';
  String _newPin = '';
  String? _error;
  bool _busy = false;

  void _onDigitTap(int digit) {
    if (_busy || _digits.length >= _pinLength) return;
    setState(() {
      _digits.add(digit);
      _error = null;
    });
    if (_digits.length == _pinLength) {
      _nextStep();
    }
  }

  void _onDelete() {
    if (_busy || _digits.isEmpty) return;
    setState(() => _digits.removeLast());
  }

  Future<void> _nextStep() async {
    final pin = _digits.join();
    setState(() => _digits.clear());

    switch (_step) {
      case ChangePinStep.verifyOld:
        setState(() {
          _oldPin = pin;
          _step = ChangePinStep.enterNew;
        });
        break;
      case ChangePinStep.enterNew:
        final pinError = widget.pinValidator.validate(pin);
        if (pinError != null) {
          setState(() {
            _error = pinError;
          });
          return;
        }
        setState(() {
          _newPin = pin;
          _step = ChangePinStep.confirmNew;
        });
        break;
      case ChangePinStep.confirmNew:
        if (pin != _newPin) {
          setState(() {
            _error = 'PINs do not match. Try again.';
            _step = ChangePinStep.enterNew;
            _newPin = '';
          });
          return;
        }
        _submit();
        break;
    }
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.changePinUseCase.execute(oldPin: _oldPin, newPin: _newPin);
      // Re-wrap the chat identity key so history stays recoverable. A failure
      // here must not read as a failed PIN change — the PIN itself did change.
      var chatKeyWarning = false;
      try {
        await widget.onPinChanged?.call(_newPin);
      } catch (_) {
        chatKeyWarning = true;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            chatKeyWarning
                ? 'PIN changed, but the chat key backup could not be updated. '
                      'Reopen Chat while online to retry.'
                : 'PIN changed successfully.',
          ),
        ),
      );
      context.pop();
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString();
        // Reset to first step if old PIN was wrong
        if (e.toString().contains('Incorrect old PIN')) {
          _step = ChangePinStep.verifyOld;
          _oldPin = '';
        } else {
          _step = ChangePinStep.enterNew;
          _newPin = '';
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final copy = switch (_step) {
      ChangePinStep.verifyOld => (
        icon: Icons.lock_outline_rounded,
        title: 'Confirm Old PIN',
        subtitle: 'Enter your current app PIN to continue.',
      ),
      ChangePinStep.enterNew => (
        icon: Icons.password_rounded,
        title: 'Enter New PIN',
        subtitle: 'Choose a new 4-digit PIN.',
      ),
      ChangePinStep.confirmNew => (
        icon: Icons.verified_user_outlined,
        title: 'Confirm New PIN',
        subtitle: 'Re-enter your new PIN.',
      ),
    };

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              _ChangePinHero(
                icon: copy.icon,
                title: copy.title,
                subtitle: copy.subtitle,
              ),
              const SizedBox(height: AppSpacing.xxl),
              PinDotRow(
                filledCount: _digits.length,
                total: _pinLength,
                hasError: _error != null,
              ),
              if (_step != ChangePinStep.verifyOld) ...[
                const SizedBox(height: AppSpacing.lg),
                const InfoBanner(
                  message:
                      'Your PIN also unlocks your chat history on a new device. '
                      'If you forget it, past messages cannot be recovered.',
                  tone: InfoBannerTone.info,
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                InfoBanner(message: _error!, tone: InfoBannerTone.error),
              ],
              if (_busy) ...[
                const SizedBox(height: AppSpacing.lg),
                const Center(child: CircularProgressIndicator()),
              ],
              const Spacer(),
              PinPad(
                onDigit: _onDigitTap,
                onDelete: _onDelete,
                enabled: !_busy,
              ),
              Text(
                'Digits are hidden while you update the vault PIN.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChangePinHero extends StatelessWidget {
  const _ChangePinHero({
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
          style: theme.textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
