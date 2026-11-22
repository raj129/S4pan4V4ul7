import 'dart:async';

import '../../domain/models/secret_entry_config.dart';

/// Detects hidden calculator gestures to open the vault lock screen or
/// silently unlock directly into chat.
///
/// The default two-key simultaneous hold (`7` + `=`) is **always** active as
/// a guaranteed fallback, even when a one-handed method is enabled. Kept
/// separate from calculator math logic so timing and accidental-touch guards
/// can be reasoned about and unit-tested independently.
class VaultTriggerDetector {
  VaultTriggerDetector({
    required this.onTriggered,
    this.onPinSubmitted,
    SecretEntryConfig config = const SecretEntryConfig(),
    Duration? holdDuration,
    this.cooldown = const Duration(milliseconds: 800),
    this.sequentialWindow = const Duration(milliseconds: 1500),
    this.multiTapWindow = const Duration(milliseconds: 600),
    this.pinCaptureTimeout = const Duration(seconds: 15),
    DateTime Function()? now,
  }) : _config = config,
       _holdDurationOverride = holdDuration,
       _now = now ?? DateTime.now;

  final void Function() onTriggered;
  final Future<bool> Function(String pin)? onPinSubmitted;
  final Duration? _holdDurationOverride;
  final Duration cooldown;
  final Duration sequentialWindow;
  final Duration multiTapWindow;
  final Duration pinCaptureTimeout;
  final DateTime Function() _now;

  SecretEntryConfig _config;
  SecretEntryConfig get config => _config;

  bool _locked = false;
  Timer? _holdTimer;
  Timer? _defaultHoldTimer;
  Timer? _cooldownTimer;
  Timer? _sequentialWindowTimer;
  Timer? _pinCaptureTimer;

  // Always-on default simultaneous hold state.
  bool _defaultHoldingPrimary = false;
  bool _defaultHoldingSecondary = false;

  // Sequential hold state.
  bool _sequentialHoldCompleted = false;
  bool _sequentialAwaitingTap = false;

  // Multi-tap + hold state.
  int _tapStreak = 0;
  DateTime? _lastTapAt;

  // Hold + PIN + Confirm key state (Method 99).
  bool _pinCaptureArmed = false;
  final StringBuffer _pinBuffer = StringBuffer();

  // Suppresses the normal calculator tap action when a hold gesture fired.
  String? _suppressTapKeyId;

  // Latest calculator display state supplied on key interactions.
  String _latestExpression = '';
  bool _latestDisplayCleared = true;

  Duration get defaultHoldDuration =>
      _holdDurationOverride ?? const Duration(milliseconds: 1200);

  Duration get holdDuration {
    if (_holdDurationOverride != null) return _holdDurationOverride;
    return switch (_config.method) {
      SecretEntryMethod.simultaneousHold => const Duration(milliseconds: 1200),
      SecretEntryMethod.holdPinConfirm => const Duration(milliseconds: 800),
      SecretEntryMethod.sequentialHold => const Duration(milliseconds: 800),
      SecretEntryMethod.secretExpressionHold => const Duration(
        milliseconds: 1000,
      ),
      SecretEntryMethod.multiTapHold => const Duration(milliseconds: 800),
      SecretEntryMethod.secretMathEquation => const Duration(
        milliseconds: 1000,
      ),
    };
  }

  bool get _defaultArmed =>
      _config.defaultPrimaryKeyId == _config.defaultSecondaryKeyId
      ? _defaultHoldingPrimary
      : (_defaultHoldingPrimary && _defaultHoldingSecondary);

  /// Exposed for unit testing of arming states.
  bool get isArmed {
    if (_defaultArmed) return true;
    if (!_config.oneHandedEnabled) return false;
    return switch (_config.method) {
      SecretEntryMethod.holdPinConfirm => _pinCaptureArmed,
      SecretEntryMethod.sequentialHold => _sequentialAwaitingTap,
      _ => false,
    };
  }

  void updateConfig(SecretEntryConfig next) {
    if (_config == next) return;
    _config = next;
    _resetTransientState();
  }

  void updateDisplayState({
    required String expression,
    required bool isCleared,
  }) {
    _latestExpression = expression;
    _latestDisplayCleared = isCleared;
  }

  /// Returns true once if [keyId]'s next `onTap` should be ignored because a
  /// long-press trigger already consumed the gesture.
  bool consumeSuppressedTap(String keyId) {
    if (_suppressTapKeyId == keyId) {
      _suppressTapKeyId = null;
      return true;
    }
    return false;
  }

  void handlePressStart(
    String keyId, {
    String? currentExpression,
    bool? isDisplayCleared,
  }) {
    if (currentExpression != null) _latestExpression = currentExpression;
    if (isDisplayCleared != null) _latestDisplayCleared = isDisplayCleared;
    if (_locked) return;

    // 1. Always-on default 7 + = simultaneous hold.
    _handleDefaultSimultaneousPressStart(keyId);

    // If both 7 and = are held together, let the default 7 + = hold win
    // without racing the one-handed timer.
    if (_defaultArmed) {
      _cancelHoldTimer();
      return;
    }

    // 2. Optional one-handed method.
    if (!_config.oneHandedEnabled) return;
    switch (_config.method) {
      case SecretEntryMethod.simultaneousHold:
        break;
      case SecretEntryMethod.holdPinConfirm:
        _handleHoldPinConfirmPressStart(keyId);
      case SecretEntryMethod.sequentialHold:
        _handleSequentialPressStart(keyId);
      case SecretEntryMethod.secretExpressionHold:
        _handleSecretExpressionPressStart(keyId);
      case SecretEntryMethod.multiTapHold:
        _handleMultiTapPressStart(keyId);
      case SecretEntryMethod.secretMathEquation:
        _handleSecretMathEquationPressStart(keyId);
    }
  }

  void handlePressEnd(String keyId) {
    if (_updateDefaultHold(keyId, held: false)) {
      _cancelDefaultHoldTimer();
    }

    if (!_config.oneHandedEnabled) return;
    switch (_config.method) {
      case SecretEntryMethod.simultaneousHold:
        break;
      case SecretEntryMethod.holdPinConfirm:
        if (keyId == _config.primaryKeyId) {
          _cancelHoldTimer();
        }
      case SecretEntryMethod.sequentialHold:
        if (keyId == _config.primaryKeyId) {
          _cancelHoldTimer();
          if (_sequentialHoldCompleted) {
            _sequentialHoldCompleted = false;
            _sequentialAwaitingTap = true;
            _sequentialWindowTimer?.cancel();
            _sequentialWindowTimer = Timer(sequentialWindow, () {
              _sequentialAwaitingTap = false;
            });
          }
        }
      case SecretEntryMethod.secretExpressionHold:
      case SecretEntryMethod.multiTapHold:
      case SecretEntryMethod.secretMathEquation:
        if (keyId == _config.primaryKeyId) {
          _cancelHoldTimer();
        }
    }
  }

  void handleKeyTap(String keyId) {
    if (_locked || !_config.oneHandedEnabled) return;

    switch (_config.method) {
      case SecretEntryMethod.simultaneousHold:
        break;
      case SecretEntryMethod.holdPinConfirm:
        _handleHoldPinConfirmTap(keyId);
      case SecretEntryMethod.sequentialHold:
        if (_sequentialAwaitingTap) {
          if (keyId == _config.secondaryKeyId) {
            _sequentialAwaitingTap = false;
            _sequentialWindowTimer?.cancel();
            _fireTriggered();
          } else if (keyId != _config.primaryKeyId) {
            _sequentialAwaitingTap = false;
            _sequentialWindowTimer?.cancel();
          }
        }
      case SecretEntryMethod.secretExpressionHold:
      case SecretEntryMethod.secretMathEquation:
        break;
      case SecretEntryMethod.multiTapHold:
        _handleMultiTapKeyTap(keyId);
    }
  }

  void _handleDefaultSimultaneousPressStart(String keyId) {
    if (!_updateDefaultHold(keyId, held: true)) return;
    if (!_defaultArmed || _defaultHoldTimer != null) return;

    _defaultHoldTimer = Timer(defaultHoldDuration, () {
      _defaultHoldTimer = null;
      if (!_defaultArmed || _locked) return;
      _defaultHoldingPrimary = false;
      _defaultHoldingSecondary = false;
      _suppressTapKeyId = keyId;
      _fireTriggered();
    });
  }

  bool _updateDefaultHold(String keyId, {required bool held}) {
    var matched = false;
    if (keyId == _config.defaultPrimaryKeyId) {
      _defaultHoldingPrimary = held;
      matched = true;
    }
    if (keyId == _config.defaultSecondaryKeyId) {
      _defaultHoldingSecondary = held;
      matched = true;
    }
    return matched;
  }

  void _handleHoldPinConfirmPressStart(String keyId) {
    if (keyId != _config.primaryKeyId) return;
    if (_holdTimer != null) return;
    _holdTimer = Timer(holdDuration, () {
      _holdTimer = null;
      if (_locked) return;
      _pinCaptureArmed = true;
      _pinBuffer.clear();
      _suppressTapKeyId = keyId;
      _pinCaptureTimer?.cancel();
      _pinCaptureTimer = Timer(pinCaptureTimeout, _disarmPinCapture);
    });
  }

  void _handleHoldPinConfirmTap(String keyId) {
    if (!_pinCaptureArmed) return;

    if (keyId == _config.confirmKeyId) {
      final pin = _pinBuffer.toString();
      _disarmPinCapture();
      if (pin.isEmpty) return;
      _startCooldown();
      unawaited(_submitStealthPin(pin));
      return;
    }

    if (keyId == 'backspace') {
      final current = _pinBuffer.toString();
      if (current.isNotEmpty) {
        _pinBuffer
          ..clear()
          ..write(current.substring(0, current.length - 1));
      }
      return;
    }

    if (keyId == 'clear') {
      _disarmPinCapture();
      return;
    }

    final digit = _digitForKeyId(keyId);
    if (digit != null) {
      _pinBuffer.write(digit);
      _pinCaptureTimer?.cancel();
      _pinCaptureTimer = Timer(pinCaptureTimeout, _disarmPinCapture);
    }
  }

  void _handleSequentialPressStart(String keyId) {
    if (keyId == _config.primaryKeyId) {
      if (_config.requireClearedDisplay && !_latestDisplayCleared) {
        return;
      }
      _sequentialAwaitingTap = false;
      _sequentialWindowTimer?.cancel();
      _sequentialHoldCompleted = false;
      _cancelHoldTimer();
      _holdTimer = Timer(holdDuration, () {
        _holdTimer = null;
        if (_locked) return;
        _sequentialHoldCompleted = true;
        _suppressTapKeyId = keyId;
      });
      return;
    }

    if (_sequentialAwaitingTap && keyId != _config.secondaryKeyId) {
      _sequentialAwaitingTap = false;
      _sequentialWindowTimer?.cancel();
    }
  }

  void _handleSecretExpressionPressStart(String keyId) {
    if (keyId != _config.primaryKeyId) return;
    if (_latestExpression.trim() != _config.secretExpression.trim()) return;
    _cancelHoldTimer();
    _holdTimer = Timer(holdDuration, () {
      _holdTimer = null;
      if (_locked) return;
      _suppressTapKeyId = keyId;
      _fireTriggered();
    });
  }

  void _handleMultiTapPressStart(String keyId) {
    if (keyId != _config.primaryKeyId) {
      _tapStreak = 0;
      _lastTapAt = null;
      return;
    }

    final lastTap = _lastTapAt;
    if (lastTap == null || _now().difference(lastTap) > multiTapWindow) {
      _tapStreak = 0;
    }

    if (_tapStreak >= _config.tapCount) {
      _cancelHoldTimer();
      _holdTimer = Timer(holdDuration, () {
        _holdTimer = null;
        if (_locked) return;
        _tapStreak = 0;
        _lastTapAt = null;
        _suppressTapKeyId = keyId;
        _fireTriggered();
      });
    }
  }

  void _handleMultiTapKeyTap(String keyId) {
    if (keyId != _config.primaryKeyId) {
      _tapStreak = 0;
      _lastTapAt = null;
      return;
    }
    final now = _now();
    final lastTap = _lastTapAt;
    if (lastTap == null || now.difference(lastTap) > multiTapWindow) {
      _tapStreak = 1;
    } else {
      _tapStreak += 1;
    }
    _lastTapAt = now;
  }

  void _handleSecretMathEquationPressStart(String keyId) {
    if (keyId != _config.primaryKeyId) return;
    final match = RegExp(r'(\d{4})$').firstMatch(_latestExpression.trim());
    if (match == null) return;
    final candidatePin = match.group(1)!;
    _cancelHoldTimer();
    _holdTimer = Timer(holdDuration, () {
      _holdTimer = null;
      if (_locked) return;
      _startCooldown();
      unawaited(_submitStealthPin(candidatePin, suppressKeyOnSuccess: keyId));
    });
  }

  Future<void> _submitStealthPin(
    String pin, {
    String? suppressKeyOnSuccess,
  }) async {
    final handler = onPinSubmitted;
    if (handler == null) return;
    final ok = await handler(pin);
    if (ok && suppressKeyOnSuccess != null) {
      _suppressTapKeyId = suppressKeyOnSuccess;
    }
  }

  void _fireTriggered() {
    _startCooldown();
    onTriggered();
  }

  void _startCooldown() {
    _locked = true;
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(cooldown, () => _locked = false);
  }

  void _disarmPinCapture() {
    _pinCaptureArmed = false;
    _pinBuffer.clear();
    _pinCaptureTimer?.cancel();
    _pinCaptureTimer = null;
  }

  void _cancelHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _cancelDefaultHoldTimer() {
    _defaultHoldTimer?.cancel();
    _defaultHoldTimer = null;
  }

  void _resetTransientState() {
    _cancelHoldTimer();
    _cancelDefaultHoldTimer();
    _sequentialWindowTimer?.cancel();
    _sequentialWindowTimer = null;
    _disarmPinCapture();
    _defaultHoldingPrimary = false;
    _defaultHoldingSecondary = false;
    _sequentialHoldCompleted = false;
    _sequentialAwaitingTap = false;
    _tapStreak = 0;
    _lastTapAt = null;
    _suppressTapKeyId = null;
  }

  static String? _digitForKeyId(String keyId) {
    if (!keyId.startsWith('digit-')) return null;
    final digit = keyId.substring('digit-'.length);
    return digit.length == 1 ? digit : null;
  }

  void dispose() {
    _cancelHoldTimer();
    _cancelDefaultHoldTimer();
    _cooldownTimer?.cancel();
    _sequentialWindowTimer?.cancel();
    _pinCaptureTimer?.cancel();
    _pinBuffer.clear();
    _cooldownTimer = null;
    _sequentialWindowTimer = null;
    _pinCaptureTimer = null;
  }
}
