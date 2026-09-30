/// Marks stretches where the app is deliberately handed to another activity
/// (camera, gallery or file picker).
///
/// Those hand-offs background the app exactly like the user leaving it, so
/// without this the background auto-lock would lock the vault while the picker
/// is still open and the user would come back to the calculator.
class ExternalActivityGuard {
  ExternalActivityGuard._();

  static int _active = 0;

  static bool get isActive => _active > 0;

  /// Runs [action] with background auto-lock suppressed until it completes.
  static Future<T> run<T>(Future<T> Function() action) async {
    _active++;
    try {
      return await action();
    } finally {
      _active--;
    }
  }
}
