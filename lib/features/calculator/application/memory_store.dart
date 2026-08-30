/// Session-scoped calculator memory register backing `MC`/`MR`/`M+`/`M-`.
class MemoryStore {
  double _value = 0;
  bool _hasValue = false;

  double get value => _value;

  /// Whether `M` should be shown as active in the UI.
  bool get hasValue => _hasValue;

  void clear() {
    _value = 0;
    _hasValue = false;
  }

  void add(double amount) {
    _value += amount;
    _hasValue = true;
  }

  void subtract(double amount) {
    _value -= amount;
    _hasValue = true;
  }

  void store(double amount) {
    _value = amount;
    _hasValue = true;
  }
}
