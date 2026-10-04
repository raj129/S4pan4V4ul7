import 'package:flutter/widgets.dart';

/// A native dialog removes Flutter window focus without backgrounding the
/// Activity. Only that inactive transition is exempt; real background locking
/// and explicit vault locks remain unchanged.
class AndroidChatViewerGuard {
  AndroidChatViewerGuard._();
  static int _viewers = 0;

  static bool suppressesLock(AppLifecycleState state) =>
      state == AppLifecycleState.inactive && _viewers > 0;

  static Future<T> run<T>(Future<T> Function() action) async {
    _viewers++;
    try {
      return await action();
    } finally {
      _viewers--;
    }
  }
}
