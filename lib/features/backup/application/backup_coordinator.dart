import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Runs backup, restore, and delete one at a time.
///
/// Two layers are needed. The in-process queue orders work within one isolate.
/// The OS file lock covers the nightly WorkManager isolate, which shares the
/// disk but not memory. POSIX file locks are per process, so the queue is still
/// required when both run in the same process. The OS releases the file lock
/// if the worker is killed, so a crash cannot leave the backup locked.
class BackupCoordinator {
  BackupCoordinator({Future<File> Function()? lockFile})
    : _lockFile = lockFile ?? _defaultLockFile;

  /// Queue only, no cross-isolate lock. For tests and in-memory setups.
  BackupCoordinator.inProcess() : _lockFile = null;

  /// Shared app-wide coordinator that also locks across isolates.
  static final shared = BackupCoordinator();

  final Future<File> Function()? _lockFile;
  Future<void> _tail = Future.value();

  static Future<File> _defaultLockFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'backup.lock'));
  }

  /// Runs [action] after every earlier call has finished. Errors from
  /// [action] are returned to the caller and do not block later work.
  Future<T> run<T>(Future<T> Function() action) {
    final done = Completer<void>();
    final previous = _tail;
    _tail = done.future;
    final result = Completer<T>();
    previous.whenComplete(() async {
      try {
        result.complete(await _withFileLock(action));
      } catch (error, stack) {
        result.completeError(error, stack);
      } finally {
        done.complete();
      }
    });
    return result.future;
  }

  Future<T> _withFileLock<T>(Future<T> Function() action) async {
    final lockFile = _lockFile;
    if (lockFile == null) return action();
    final file = await lockFile();
    await file.parent.create(recursive: true);
    final handle = await file.open(mode: FileMode.write);
    try {
      await handle.lock(FileLock.exclusive);
      try {
        return await action();
      } finally {
        await handle.unlock();
      }
    } finally {
      await handle.close();
    }
  }
}
