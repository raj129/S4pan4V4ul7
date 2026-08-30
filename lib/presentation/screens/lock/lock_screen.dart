import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/services/pin_validator.dart';
import '../../../application/usecases/unlock_vault_usecase.dart';

class LockScreen extends StatefulWidget {
  const LockScreen({
    required this.unlockVaultUseCase,
    required this.pinValidator,
    required this.onUnlocked,
    this.title = 'Unlock Vault',
    this.subtitle = 'This PIN is separate from your device PIN.',
    super.key,
  });

  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;
  final VoidCallback onUnlocked;
  final String title;
  final String subtitle;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  static const int _pinLength = PinValidator.requiredLength;
  static const List<int> _lockoutScheduleSeconds = <int>[0, 0, 0, 10, 30, 60];
  final _digits = <int>[];
  bool _unlocking = false;
  String? _error;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  @override
  void initState() {
    super.initState();
  }

  void _onDigitTap(int digit) {
    if (_isTemporarilyLocked) return;
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
    if (_isTemporarilyLocked) {
      setState(() {
        _error = _lockoutMessage;
      });
      return;
    }
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
      _failedAttempts = 0;
      _lockedUntil = null;
      widget.onUnlocked();
      return;
    }
    _failedAttempts += 1;
    final lockSeconds = _lockoutScheduleSeconds[_failedAttempts.clamp(
      0,
      _lockoutScheduleSeconds.length - 1,
    )];
    if (lockSeconds > 0) {
      _lockedUntil = DateTime.now().add(Duration(seconds: lockSeconds));
    }
    setState(() {
      _unlocking = false;
      _error = _isTemporarilyLocked ? _lockoutMessage : 'Incorrect PIN. Try again.';
    });
  }

  bool get _isTemporarilyLocked {
    final until = _lockedUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  String get _lockoutMessage {
    final until = _lockedUntil;
    if (until == null) {
      return 'Too many failed attempts. Try again later.';
    }
    final seconds = until.difference(DateTime.now()).inSeconds;
    return 'Too many failed attempts. Try again in ${seconds > 0 ? seconds : 1}s.';
  }

  @override
  void dispose() {
    _digits.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter your app PIN',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.subtitle,
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
            if (_isTemporarilyLocked) ...[
              const SizedBox(height: 8),
              Text(
                _lockoutMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_unlocking) ...[
              const SizedBox(height: 12),
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
