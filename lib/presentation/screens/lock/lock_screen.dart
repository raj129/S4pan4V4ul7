import 'package:flutter/material.dart';

import '../../../application/services/pin_validator.dart';
import '../../../application/usecases/unlock_vault_usecase.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/pin/pin_pad.dart';

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
    setState(() {
      _digits.add(digit);
      _error = null;
    });
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
    final lockSeconds =
        _lockoutScheduleSeconds[_failedAttempts.clamp(
          0,
          _lockoutScheduleSeconds.length - 1,
        )];
    if (lockSeconds > 0) {
      _lockedUntil = DateTime.now().add(Duration(seconds: lockSeconds));
    }
    setState(() {
      _unlocking = false;
      _error = _isTemporarilyLocked
          ? _lockoutMessage
          : 'Incorrect PIN. Try again.';
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
    final theme = Theme.of(context);
    final locked = _isTemporarilyLocked;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Padding(
          padding: AppSpacing.page,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xxl),
              _LockHero(title: 'Enter your app PIN', subtitle: widget.subtitle),
              const SizedBox(height: AppSpacing.xxl),
              PinDotRow(
                filledCount: _digits.length,
                total: _pinLength,
                hasError: _error != null,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.lg),
                InfoBanner(message: _error!, tone: InfoBannerTone.error),
              ] else if (locked) ...[
                const SizedBox(height: AppSpacing.lg),
                InfoBanner(
                  message: _lockoutMessage,
                  tone: InfoBannerTone.warning,
                ),
              ] else
                const SizedBox(height: AppSpacing.xl),
              if (_unlocking) ...[
                const SizedBox(height: AppSpacing.lg),
                const Center(child: CircularProgressIndicator()),
              ],
              const Spacer(),
              PinPad(
                onDigit: _onDigitTap,
                onDelete: _onDelete,
                enabled: !_unlocking && !locked,
              ),
              Text(
                locked
                    ? 'PIN entry is temporarily paused.'
                    : 'Your vault stays locked until the PIN is verified.',
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

class _LockHero extends StatelessWidget {
  const _LockHero({required this.title, required this.subtitle});

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
            Icons.lock_open_outlined,
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
