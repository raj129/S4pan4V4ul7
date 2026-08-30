import '../domain/models/history_entry.dart';

/// Session-scoped calculation history.
///
/// Deliberately in-memory only: nothing is written to disk, so the decoy
/// calculator leaves no trace of use between launches.
class HistoryStore {
  HistoryStore({this.capacity = 100});

  final int capacity;
  final List<HistoryEntry> _entries = <HistoryEntry>[];

  /// Most recent entry first.
  List<HistoryEntry> get entries => List<HistoryEntry>.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  void add(HistoryEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > capacity) {
      _entries.removeRange(capacity, _entries.length);
    }
  }

  void clear() => _entries.clear();
}
