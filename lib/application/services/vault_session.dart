import 'dart:convert';

import 'package:flutter/foundation.dart';

class VaultLockedException implements Exception {
  final String message;
  VaultLockedException([this.message = 'Vault session is locked.']);

  @override
  String toString() => 'VaultLockedException: $message';
}

class VaultSession extends ChangeNotifier {
  String? _vaultId;
  List<int>? _vmk;
  List<int>? _pinBytes;

  bool get isUnlocked => _vaultId != null && _vmk != null && _vmk!.isNotEmpty;
  String? get vaultId => _vaultId;

  /// The PIN for the current unlocked session, or null when locked.
  ///
  /// Held because the chat identity key is wrapped under a PIN-derived KEK, and
  /// that wrap/unwrap happens after Google sign-in — long after the lock screen
  /// has been dismissed. Kept as bytes so the long-lived copy can be zeroed on
  /// [lock]; the returned String cannot be, as Dart strings are immutable.
  String? get pin {
    final bytes = _pinBytes;
    if (bytes == null || bytes.isEmpty) return null;
    return utf8.decode(bytes);
  }

  List<int> requireVmk() {
    final vmk = _vmk;
    if (_vaultId == null || vmk == null || vmk.isEmpty) {
      throw VaultLockedException();
    }
    return List<int>.from(vmk);
  }

  void unlock({
    required String vaultId,
    required List<int> vmkBytes,
    String? pin,
  }) {
    lock();
    _vaultId = vaultId;
    _vmk = List<int>.from(vmkBytes);
    _pinBytes = pin == null ? null : utf8.encode(pin);
    notifyListeners();
  }

  void lock() {
    _zero(_vmk);
    _zero(_pinBytes);
    _vmk = null;
    _pinBytes = null;
    _vaultId = null;
    notifyListeners();
  }

  static void _zero(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return;
    try {
      bytes.fillRange(0, bytes.length, 0);
    } catch (_) {}
  }
}
