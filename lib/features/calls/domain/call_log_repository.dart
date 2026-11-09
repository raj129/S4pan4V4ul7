import 'call_log_entry.dart';

/// Thrown when the platform call log cannot be read.
class CallLogException implements Exception {
  const CallLogException(this.message);

  final String message;

  @override
  String toString() => 'CallLogException: $message';
}

/// Access to the device call log. Unsupported platforms report empty results
/// or `false`; read failures throw [CallLogException] so the UI can show them.
abstract class CallLogRepository {
  bool get isSupported;

  /// Asks for read and write access if not already granted. True when both
  /// are granted.
  Future<bool> requestPermissions();

  /// Throws [CallLogException] when the log cannot be read.
  Future<List<CallLogEntry>> list({int limit = 500});

  /// Writes an entry into the system call log. False when the write failed.
  Future<bool> add({
    required String number,
    required CallLogType type,
    required DateTime timestamp,
    String? name,
    int durationSeconds = 0,
  });

  /// Changes the time and duration of an existing entry. False when the
  /// update failed or matched no row.
  Future<bool> update({
    required String id,
    required DateTime timestamp,
    required int durationSeconds,
  });
}
