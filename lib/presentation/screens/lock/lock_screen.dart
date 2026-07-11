import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/services/biometric_service.dart';
import '../../../application/services/pin_validator.dart';
import '../../../application/usecases/unlock_vault_usecase.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({
    required this.unlockVaultUseCase,
    required this.pinValidator,
    required this.biometricService,
    required this.biometricEnabled,
    required this.onUnlocked,
    super.key,
  });

  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;
  final BiometricService biometricService;
  final bool biometricEnabled;
  final VoidCallback onUnlocked;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const int _pinLength = 6;
  final _digits = <int>[];
  bool _unlocking = false;
  String? _error;
  bool _promptedBiometric = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometricUnlock();
    });
  }

  void _onDigitTap(int digit) {
    if (_unlocking || _digits.length >= _pinLength) return;
    setState(() => _digits.add(digit));
    if (_digits.length == _pinLength) {
      _submit();
    }
  }

  void _onDelete() {
    if (_unlocking || _digits.isEmpty) return;
    setState(() => _digits.removeLast());
  }

  Future<void> _submit() async {
    final pin = _digits.join();
    setState(() {
      _unlocking = true;
      _error = null;
      _digits.clear();
    });

    final pinError = widget.pinValidator.validate(pin);
    if (pinError != null) {
      setState(() {
        _unlocking = false;
        _error = pinError;
      });
      return;
    }

    final ok = await widget.unlockVaultUseCase.execute(pin);
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _unlocking = false;
      _error = 'Incorrect PIN. Try again.';
    });
  }

  Future<void> _tryBiometricUnlock() async {
    if (!widget.biometricEnabled || _promptedBiometric || _unlocking) return;
    _promptedBiometric = true;
    final availability = await widget.biometricService.checkAvailability();
    if (!mounted || availability != BiometricAvailability.available) return;
    setState(() {
      _unlocking = true;
      _error = null;
    });
    final ok = await widget.biometricService.authenticate(
      reason: 'Unlock your encrypted photo vault',
    );
    if (!mounted) return;
    if (ok) {
      widget.onUnlocked();
      return;
    }
    setState(() {
      _unlocking = false;
      _error = 'Biometric unlock canceled. Enter your app PIN.';
    });
  }

  @override
  void dispose() {
    _digits.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Unlock Vault')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.biometricEnabled ? 'Unlock with biometric or PIN' : 'Enter your app PIN',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This PIN is separate from your device PIN.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _PinDotRow(filledCount: _digits.length, total: _pinLength),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_unlocking) ...[
              const SizedBox(height: 12),
              const Center(child: CircularProgressIndicator()),
            ],
            if (widget.biometricEnabled && !_unlocking) ...[
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: _tryBiometricUnlock,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Try biometric again'),
                ),
              ),
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
                : Theme.of(context).colorScheme.outline,
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
