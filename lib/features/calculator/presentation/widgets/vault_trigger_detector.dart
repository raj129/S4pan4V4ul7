import 'dart:async';

import 'keypad_layouts.dart';

/// Detects the hidden vault gesture: holding `7` and `=` together.
///
/// Kept deliberately separate from the calculator logic so the gesture's
/// timing can be reasoned about (and tested) on its own. It renders nothing
/// and must never surface any hint in the UI.
class VaultTriggerDetector {
  VaultTriggerDetector({
    required this.onTriggered,    this.holdDuration = const Duration(milliseconds: 1200),
    this.cooldown = const Duration(milliseconds: 800),
  });

  final void Function() onTriggered;
  final Duration holdDuration;
  final Duration cooldown;

  bool _holdingSeven = false;
  bool _holdingEquals = false;
  bool _locked = false;
  Timer? _holdTimer;
  Timer? _cooldownTimer;

  bool get isArmed => _holdingSeven && _holdingEquals;

  void handlePressStart(String keyId) {
    if (_locked) return;
    if (!_updateHold(keyId, held: true)) return;
    if (!isArmed || _holdTimer != null) return;

    _holdTimer = Timer(holdDuration, () {
      _holdTimer = null;
      if (!isArmed || _locked) return;
      _locked = true;
      _holdingSeven = false;
      _holdingEquals = false;
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(cooldown, () => _locked = false);
      onTriggered();
    });
  }

  void handlePressEnd(String keyId) {
    if (!_updateHold(keyId, held: false)) return;
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  /// Returns true when [keyId] is one of the two trigger keys.
  bool _updateHold(String keyId, {required bool held}) {
    if (keyId == kSevenKeyId) {
      _holdingSeven = held;
      return true;
    }
    if (keyId == kEqualsKeyId) {
      _holdingEquals = held;
      return true;
    }
    return false;
  }

  void dispose() {
    _holdTimer?.cancel();
    _cooldownTimer?.cancel();
    _holdTimer = null;
    _cooldownTimer = null;
  }
}
