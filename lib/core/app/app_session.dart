import 'package:flutter/foundation.dart';

import '../../domain/entities/user_mode.dart';

/// Mutable, observable session state shared between the app root and the
/// router's redirect logic.
///
/// Previously these three pieces of state (`_lastKnownMode`,
/// `_photoSyncEnabled`, `_sessionUnlocked`) were separate fields scattered
/// across `_VaultAppState`, with only the unlocked flag wired up as a
/// `ValueNotifier` for `GoRouter.refreshListenable`. Bundling them here
/// gives the router a single source of truth and makes the unlock/lock
/// transition testable without a widget tree.
class AppSessionState extends ChangeNotifier {
  AppSessionState({UserMode initialMode = UserMode.localOnly})
      : _mode = initialMode;

  UserMode _mode;
  bool _calculatorOnboardingCompleted = false;
  bool _photoSyncEnabled = false;
  bool _unlocked = false;

  UserMode get mode => _mode;
  bool get calculatorOnboardingCompleted => _calculatorOnboardingCompleted;
  bool get photoSyncEnabled => _photoSyncEnabled;
  bool get isUnlocked => _unlocked;

  set mode(UserMode value) {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
  }

  set calculatorOnboardingCompleted(bool value) {
    if (_calculatorOnboardingCompleted == value) return;
    _calculatorOnboardingCompleted = value;
    notifyListeners();
  }

  set photoSyncEnabled(bool value) {
    if (_photoSyncEnabled == value) return;
    _photoSyncEnabled = value;
    notifyListeners();
  }

  void unlock() {
    if (_unlocked) return;
    _unlocked = true;
    notifyListeners();
  }

  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    notifyListeners();
  }
}
