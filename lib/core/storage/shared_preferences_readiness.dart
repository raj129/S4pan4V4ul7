import 'package:shared_preferences/shared_preferences.dart';

class SharedPreferencesReadiness {
  SharedPreferencesReadiness({Future<void> Function()? load})
    : _load = load ?? _loadSharedPreferences;

  static final instance = SharedPreferencesReadiness();

  final Future<void> Function() _load;
  Future<void>? _initializing;
  bool _isReady = false;

  static Future<void> _loadSharedPreferences() async {
    await SharedPreferences.getInstance();
  }

  bool get isReady => _isReady;

  Future<void> ensureInitialized() {
    if (_isReady) return Future<void>.value();
    return _initializing ??= _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _load();
      _isReady = true;
    } finally {
      _initializing = null;
    }
  }
}
