import 'package:flutter/foundation.dart';

/// What the Backup screen shows while a backup or restore is running.
@immutable
class BackupProgress {
  const BackupProgress({required this.label, this.done = 0, this.total});

  final String label;
  final int done;

  /// Null when the amount of work is unknown.
  final int? total;

  /// Fraction complete, or null when unknown (the bar shows as indeterminate).
  double? get fraction {
    final t = total;
    if (t == null || t == 0) return null;
    return done / t;
  }
}

/// Foreground progress for backup and restore, shown in Settings.
///
/// Deliberately not a notification: the nightly background run has no UI and
/// reports nothing here.
class BackupProgressReporter {
  final ValueNotifier<BackupProgress?> state = ValueNotifier(null);

  void begin(String label, {int? total}) {
    state.value = BackupProgress(label: label, total: total);
  }

  void update(int done) {
    final current = state.value;
    if (current == null) return;
    state.value = BackupProgress(
      label: current.label,
      done: done,
      total: current.total,
    );
  }

  void end() {
    state.value = null;
  }
}

final backupProgress = BackupProgressReporter();
