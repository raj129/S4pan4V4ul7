import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../application/services/pin_validator.dart';
import '../../../application/usecases/change_pin_usecase.dart';

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
      await widget.changePinUseCase.execute(
        oldPin: _oldPin,
        newPin: _newPin,
      );
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
    String title = '';
    String subtitle = '';

    switch (_step) {
      case ChangePinStep.verifyOld:
        title = 'Confirm Old PIN';
        subtitle = 'Enter your current app PIN to continue.';
        break;
      case ChangePinStep.enterNew:
        title = 'Enter New PIN';
        subtitle = 'Choose a new 4-digit PIN.';
        break;
      case ChangePinStep.confirmNew:
        title = 'Confirm New PIN';
        subtitle = 'Re-enter your new PIN.';
        break;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Change PIN')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _PinDotRow(filledCount: _digits.length, total: _pinLength),
            if (_step != ChangePinStep.verifyOld) ...[
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your PIN also unlocks your chat history on a new device. '
                      'If you forget it, past messages cannot be recovered.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 24),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 24),
              const Center(child: CircularProgressIndicator()),
            ],
            const Spacer(),
            _PinPad(onDigit: _onDigitTap, onDelete: _onDelete),
          ],
        ),
      ),
    );
  }
}

class _PinDotRow extends StatelessWidget {
  const _PinDotRow({required this.filledCount, required this.total});
  final int filledCount;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (index) {
        final filled = index < filledCount;
        return Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        );
      }),
    );
  }
}

class _PinPad extends StatelessWidget {
  const _PinPad({required this.onDigit, required this.onDelete});
  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;

  static const _layout = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9],
    [-1, 0, -2],
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
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
  const _PinKey({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

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
