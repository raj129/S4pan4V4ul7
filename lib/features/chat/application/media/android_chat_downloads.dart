import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import './media_send_status.dart';

/// The native journal owns downloads across routes, engines and process death.
/// This bridge observes it; it never starts a second Dart download queue.
class AndroidChatDownloads extends ChangeNotifier {
  AndroidChatDownloads({
    required this.currentUid,
    MethodChannel channel = const MethodChannel('photo_vault/chat_downloads'),
    this.pollInterval = const Duration(milliseconds: 500),
    this.stallTimeout = const Duration(minutes: 2),
  }) : _channel = channel;

  final String? Function() currentUid;
  final MethodChannel _channel;
  final Duration pollInterval;
  final Duration stallTimeout;
  final Map<String, AndroidDownloadJob> _jobs = {};
  final Map<String, _DownloadAcquisition> _acquisitions = {};
  Timer? _timer;
  bool _refreshing = false;
  bool _disposed = false;
  int _generation = 0;
  Object? _readError;

  String _key(String uid, String path) => '$uid:$path';
  AndroidDownloadJob? job(String path) {
    final uid = currentUid();
    return uid == null ? null : _jobs[_key(uid, path)];
  }

  void _check(String uid, [int? generation]) {
    if (_disposed ||
        currentUid() != uid ||
        (generation != null && generation != _generation)) {
      throw const ChatDownloadCancelled();
    }
  }

  Future<void> _refresh() async {
    if (_disposed || _refreshing) return;
    final uid = currentUid();
    if (uid == null || uid.isEmpty) return;
    final generation = _generation;
    _refreshing = true;
    try {
      final values = await _channel.invokeListMethod<Object?>('list');
      _check(uid, generation);
      final next = <String, AndroidDownloadJob>{};
      for (final value in values ?? const []) {
        if (value is! Map) {
          throw const FormatException('Invalid download journal.');
        }
        final job = AndroidDownloadJob.fromMap(
          Map<Object?, Object?>.from(value),
        );
        if (job.uid == uid) next[_key(uid, job.storagePath)] = job;
      }
      _jobs
        ..clear()
        ..addAll(next);
      _readError = null;
      notifyListeners();
    } on PlatformException catch (error) {
      _readError = error;
    } on MissingPluginException catch (error) {
      _readError = error;
    } on FormatException catch (error) {
      _readError = error;
    } on ChatDownloadCancelled {
      // Account changes fence the requesting acquisition below.
    } finally {
      _refreshing = false;
    }
  }

  Future<Uint8List> acquire({
    required String uid,
    required String threadId,
    required String storagePath,
    String? senderId,
  }) async {
    _check(uid);
    if (senderId == uid) {
      throw const ChatDownloadFailed(
        'Sent attachments must be opened from their original source or encrypted local copy.',
      );
    }
    final generation = _generation;
    final key = _key(uid, storagePath);
    final acquisition = _acquisitions.putIfAbsent(
      key,
      () => _DownloadAcquisition(
        _acquire(uid, threadId, storagePath, generation, senderId),
      ),
    );
    acquisition.consumers++;
    Uint8List? source;
    try {
      source = await acquisition.future;
      _check(uid, generation);
      return Uint8List.fromList(source);
    } finally {
      acquisition.consumers--;
      if (acquisition.consumers == 0) {
        if (identical(_acquisitions[key], acquisition)) {
          _acquisitions.remove(key);
        }
        source?.fillRange(0, source.length, 0);
      }
      if (_acquisitions.isEmpty) {
        _timer?.cancel();
        _timer = null;
      }
    }
  }

  Future<Uint8List> _acquire(
    String uid,
    String thread,
    String path,
    int generation,
    String? senderId,
  ) async {
    await _channel.invokeMethod<void>('enqueue', {
      'uid': uid,
      'threadId': thread,
      'storagePath': path,
      'senderId': ?senderId,
    });
    _check(uid, generation);
    _timer ??= Timer.periodic(pollInterval, (_) => unawaited(_refresh()));
    var lastProgress = -1;
    var observed = false;
    var stalledSince = DateTime.now();
    while (true) {
      _check(uid, generation);
      await _refresh();
      _check(uid, generation);
      if (_readError case final Object error) throw error;
      final current = _jobs[_key(uid, path)];
      if (current == null && observed) {
        throw const ChatDownloadFailed(
          'Encrypted download was cleaned up. Retry to download it again.',
        );
      }
      if (current != null) {
        observed = true;
        if (current.state == MediaUploadLifecycle.completed) {
          final reply = await _channel.invokeMethod<Uint8List>('read', {
            'uid': uid,
            'storagePath': path,
          });
          final bytes = reply == null ? null : Uint8List.fromList(reply);
          try {
            _check(uid, generation);
            if (bytes == null ||
                bytes.isEmpty ||
                bytes.length > 64 * 1024 * 1024) {
              throw const FormatException(
                'Downloaded attachment is empty or too large.',
              );
            }
            return bytes;
          } catch (_) {
            bytes?.fillRange(0, bytes.length, 0);
            rethrow;
          }
        }
        if (current.state == MediaUploadLifecycle.cancelled) {
          throw const ChatDownloadCancelled();
        }
        if (current.state == MediaUploadLifecycle.failed) {
          throw ChatDownloadFailed(
            current.error ?? 'Attachment download failed.',
          );
        }
        // A paused/offline queue has no whole-file deadline. Only a running
        // transfer with no byte movement is considered stalled.
        if (current.processedBytes != lastProgress ||
            current.state != MediaUploadLifecycle.uploading) {
          lastProgress = current.processedBytes;
          stalledSince = DateTime.now();
        } else if (DateTime.now().difference(stalledSince) > stallTimeout) {
          throw TimeoutException(
            'Download stopped making progress. Retry to resume.',
          );
        }
      }
      await Future<void>.delayed(pollInterval);
    }
  }

  /// Read an already-downloaded legacy sent copy, without enqueueing a job.
  Future<Uint8List?> readCompleted(String uid, String path) async {
    final generation = _generation;
    _check(uid, generation);
    await _refresh();
    _check(uid, generation);
    if (_readError case final Object error) throw error;
    if (job(path)?.state != MediaUploadLifecycle.completed) return null;
    final reply = await _channel.invokeMethod<Uint8List>('read', {
      'uid': uid,
      'storagePath': path,
    });
    _check(uid, generation);
    if (reply == null || reply.isEmpty || reply.length > 64 * 1024 * 1024) {
      throw const FormatException(
        'Completed encrypted attachment is unavailable.',
      );
    }
    return Uint8List.fromList(reply);
  }

  Future<void> command(String path, String action) async {
    final uid = currentUid();
    if (uid == null || uid.isEmpty) throw const ChatDownloadCancelled();
    if (!const {
      'pause',
      'resume',
      'retry',
      'cancel',
      'acknowledge',
    }.contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    await _channel.invokeMethod<void>(action, {
      'uid': uid,
      'storagePath': path,
    });
    await _refresh();
  }

  /// Acknowledge only after a durable completed-ciphertext commit.
  /// Preview/import must still authenticate the payload before use.
  Future<void> acknowledge(String uid, String path) async {
    _check(uid);
    await _channel.invokeMethod<void>('acknowledge', {
      'uid': uid,
      'storagePath': path,
    });
  }

  void clearAccount() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    _acquisitions.clear();
    _jobs.clear();
    _readError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

class AndroidDownloadJob {
  const AndroidDownloadJob({
    required this.uid,
    required this.storagePath,
    required this.threadId,
    required this.state,
    required this.processedBytes,
    required this.totalBytes,
    this.error,
  });
  final String uid;
  final String storagePath;
  final String threadId;
  final MediaUploadLifecycle state;
  final int processedBytes;
  final int totalBytes;
  final String? error;

  factory AndroidDownloadJob.fromMap(Map<Object?, Object?> map) {
    String text(String name) {
      final value = map[name];
      if (value is! String || value.isEmpty) {
        throw FormatException('Invalid download $name.');
      }
      return value;
    }

    int number(String name) {
      final value = map[name];
      if (value is! int || value < 0 || value > 64 * 1024 * 1024) {
        throw FormatException('Invalid download $name.');
      }
      return value;
    }

    final state = MediaUploadLifecycle.values
        .where((s) => s.name == text('state'))
        .firstOrNull;
    if (state == null) throw const FormatException('Invalid download state.');
    final processed = number('processedBytes');
    final total = number('totalBytes');
    if (total > 0 && processed > total) {
      throw const FormatException('Invalid download offset.');
    }
    if (map['error'] != null && map['error'] is! String) {
      throw const FormatException('Invalid download error.');
    }
    return AndroidDownloadJob(
      uid: text('uid'),
      threadId: text('threadId'),
      storagePath: text('storagePath'),
      state: state,
      processedBytes: processed,
      totalBytes: total,
      error: map['error'] as String?,
    );
  }

  MediaSendStatus get progress => MediaSendStatus(
    phase: MediaSendPhase.uploading,
    lifecycle: state,
    processedBytes: processedBytes,
    totalBytes: totalBytes,
    progress: totalBytes == 0 ? 0 : processedBytes / totalBytes,
  );
  String get label => switch (state) {
    MediaUploadLifecycle.uploading => 'Downloading…',
    MediaUploadLifecycle.completed => 'Download complete',
    MediaUploadLifecycle.failed => 'Download failed',
    MediaUploadLifecycle.queued => 'Download queued',
    MediaUploadLifecycle.paused => 'Download paused',
    MediaUploadLifecycle.cancelled => 'Download cancelled',
    MediaUploadLifecycle.retrying => 'Retrying download…',
    MediaUploadLifecycle.resumed => 'Resuming download…',
  };
}

class _DownloadAcquisition {
  _DownloadAcquisition(this.future);
  final Future<Uint8List> future;
  int consumers = 0;
}

class ChatDownloadCancelled implements Exception {
  const ChatDownloadCancelled();
  @override
  String toString() =>
      'Attachment download was cancelled or the account changed.';
}

class ChatDownloadFailed implements Exception {
  const ChatDownloadFailed(this.message);
  final String message;
  @override
  String toString() => message;
}
