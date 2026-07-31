import 'package:flutter/material.dart';

import '../../application/services/pin_validator.dart';
import '../../application/usecases/unlock_vault_usecase.dart';

Future<bool> requirePinReauth({
  required BuildContext context,
  required UnlockVaultUseCase unlockVaultUseCase,
  required PinValidator pinValidator,
  required String actionLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _PinReauthDialog(
      unlockVaultUseCase: unlockVaultUseCase,
      pinValidator: pinValidator,
      actionLabel: actionLabel,
    ),
  );
  return confirmed == true;
}

class _PinReauthDialog extends StatefulWidget {
  const _PinReauthDialog({
    required this.unlockVaultUseCase,
    required this.pinValidator,
    required this.actionLabel,
  });

  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;
  final String actionLabel;

  @override
  State<_PinReauthDialog> createState() => _PinReauthDialogState();
}

class _PinReauthDialogState extends State<_PinReauthDialog> {
  static const _lockoutScheduleSeconds = <int>[0, 0, 0, 10, 30, 60];
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;
  int _failedAttempts = 0;
  DateTime? _lockedUntil;

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

  Future<void> _submit() async {
    if (_submitting) return;
    if (_isTemporarilyLocked) {
      setState(() => _error = _lockoutMessage);
      return;
    }

    final pin = _controller.text.trim();
    final pinError = widget.pinValidator.validate(pin);
    if (pinError != null) {
      setState(() => _error = pinError);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    final ok = await widget.unlockVaultUseCase.execute(pin);
    if (!mounted) return;

    if (ok) {
      Navigator.of(context).pop(true);
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
      _submitting = false;
      _controller.clear();
      _error = _isTemporarilyLocked ? _lockoutMessage : 'Incorrect PIN. Try again.';
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirm app PIN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Enter your 4-digit PIN to ${widget.actionLabel}.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_submitting && !_isTemporarilyLocked,
            keyboardType: TextInputType.number,
            maxLength: PinValidator.requiredLength,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'App PIN',
              counterText: '',
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_submitting) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_submitting || _isTemporarilyLocked) ? null : _submit,
          child: const Text('Confirm'),
        ),
      ],
    );
  }
}
