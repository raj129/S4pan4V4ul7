import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../crypto/chat_crypto_service.dart';
import '../../domain/repositories/message_repository.dart';
import 'chat_media_cache.dart';
import 'android_chat_downloads.dart';
import 'android_chat_local_media.dart';
import 'chat_media_timings.dart';
import './media_send_status.dart';

/// Shared, observable attachment decryption with bounded plaintext memory.
class ChatMediaLoader extends ChangeNotifier {
  ChatMediaLoader({
    required this.mediaRepository,
    required this.cryptoService,
    ChatMediaCache? diskCache,
    this.maxMemoryBytes = 32 * 1024 * 1024,
    this.loadTimeout = const Duration(seconds: 45),
    this.maxConcurrentLoads = 6,
    String accountId = '',
    this.downloads,
    this.localMedia,
  }) : diskCache = diskCache ?? ChatMediaCache(),
       _scheduler = _MediaScheduler(maxConcurrentLoads),
       _accountId = accountId;

  final _MediaScheduler _scheduler;
  final int maxConcurrentLoads;
  final MediaRepository mediaRepository;
  final ChatCryptoService cryptoService;
  final ChatMediaCache diskCache;
  final int maxMemoryBytes;
  final Duration loadTimeout;
  final AndroidChatDownloads? downloads;
  final AndroidChatLocalMedia? localMedia;
  final Map<String, Object> _failures = {};
  final Set<String> _sentPaths = {};
  bool isSent(String path) => _sentPaths.contains(path);
  final Map<String, String> _stages = {};
  String? stage(String path) => _stages[path];
  Future<void> retryFailedDownload(String path) async {
    if (isSent(path)) return;
    if (_failures[path] case ChatLocalMediaException(
      code: 'local_media_corrupt',
    )) {
      await diskCache.remove(diskKey(path));
      await downloads?.command(path, 'cancel');
      _failures.remove(path);
    }
    final state = downloads?.job(path)?.state;
    if (state == MediaUploadLifecycle.failed ||
        state == MediaUploadLifecycle.cancelled) {
      await downloads?.command(path, 'retry');
    }
  }

  final Map<String, Uint8List> _cache = {};
  final Map<String, _MediaAcquisition> _inFlight = {};
  final Map<String, int> _pathEpoch = {};
  String _accountId;
  int _generation = 0;
  int _memoryBytes = 0;
  bool _disposed = false;

  String get accountId => _accountId;
  String diskKey(String storagePath) => '$_accountId:$storagePath';

  Future<int> cachedSize(String storagePath) =>
      diskCache.sizeOf(diskKey(storagePath));

  void setAccount(String uid) {
    if (_accountId == uid) return;
    _accountId = uid;
    clear();
  }

  Uint8List? cached(String storagePath) {
    final bytes = _cache.remove(storagePath);
    if (bytes != null) _cache[storagePath] = bytes;
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  void seed(String storagePath, Uint8List bytes) {
    if (_disposed || bytes.isEmpty || bytes.length > maxMemoryBytes) return;
    final old = _cache.remove(storagePath);
    if (old != null) {
      _memoryBytes -= old.length;
      old.fillRange(0, old.length, 0);
    }
    while (_memoryBytes + bytes.length > maxMemoryBytes && _cache.isNotEmpty) {
      final removed = _cache.remove(_cache.keys.first)!;
      _memoryBytes -= removed.length;
      removed.fillRange(0, removed.length, 0);
    }
    // Own the buffer; clearing must not overwrite a caller's upload input.
    _cache[storagePath] = Uint8List.fromList(bytes);
    _memoryBytes += bytes.length;
    notifyListeners();
  }

  Future<Uint8List> load({
    required String threadId,
    required String storagePath,
    String? senderId,
    ChatMediaLoadToken? token,
  }) {
    if (localMedia != null && senderId == _accountId) {
      _sentPaths.add(storagePath);
    }
    final hit = cached(storagePath);
    if (hit != null) return Future.value(hit);
    final key = '$threadId:$storagePath:$senderId';
    final running = _inFlight[key];
    if (running != null) {
      // A re-request (tile scrolled back into view) moves it to the front.
      _scheduler.promote(running.task);
      return _own(running, token);
    }
    final ticket = _ticket(storagePath);
    late final _MediaAcquisition acquisition;
    late final Future<Uint8List> future;
    final started = Stopwatch()..start();
    final sent = senderId == _accountId;
    final task = _scheduler.submit(() {
      if (_disposed || ticket.generation != _generation) {
        throw const ChatMediaLoadCancelled();
      }
      _log(
        'ChatMedia start path=$storagePath sent=$sent queuedMs=${started.elapsedMilliseconds}',
      );
      final download =
          _download(
            threadId,
            storagePath,
            ticket,
            cachePlaintext: true,
            senderId: senderId,
          ).then<Uint8List>(
            (bytes) {
              _log(
                'ChatMedia ok path=$storagePath sent=$sent bytes=${bytes.length} ms=${started.elapsedMilliseconds}',
              );
              return bytes;
            },
            onError: (Object error, StackTrace stack) {
              _log(
                  'ChatMedia fail path=$storagePath sent=$sent stage=${_stages[storagePath]} '
                  'error=${error.runtimeType} $error ms=${started.elapsedMilliseconds}',
                );
              throw error;
            },
          );
      return downloads == null
          ? download.timeout(
              loadTimeout,
              onTimeout: () {
                ticket.active = false;
                throw TimeoutException(
                  'Attachment download timed out.',
                  loadTimeout,
                );
              },
            )
          : download;
    });
    future = task.future.whenComplete(() {
      ticket.active = false;
      if (identical(_inFlight[key], acquisition)) _inFlight.remove(key);
    });
    acquisition = _MediaAcquisition(future, _generation, task);
    _inFlight[key] = acquisition;
    return _own(acquisition, token);
  }

  Future<Uint8List> _own(
    _MediaAcquisition acquisition,
    ChatMediaLoadToken? token,
  ) async {
    acquisition.consumers++;
    var released = false;
    void release() {
      if (released) return;
      released = true;
      acquisition.waiting--;
      // Nobody wants it any more and it has not started: drop it.
      if (acquisition.waiting == 0) {
        _scheduler.cancelQueued(acquisition.task);
      }
    }

    acquisition.waiting++;
    token?._attach(release);
    Uint8List? source;
    try {
      source = await acquisition.future;
      if (_disposed || acquisition.generation != _generation) {
        throw const ChatMediaLoadCancelled();
      }
      return Uint8List.fromList(source);
    } finally {
      release();
      if (--acquisition.consumers == 0) {
        source?.fillRange(0, source.length, 0);
      }
    }
  }

  Future<Uint8List> _loadSent(
    String threadId,
    String path,
    _LoadTicket ticket,
  ) async {
    final uid = _accountId;
    final metadata = await localMedia!.metadata(uid, path);
    _check(ticket);
    if (metadata?.sourceUri != null) {
      try {
        final original = await localMedia!.readOriginal(uid, metadata!);
        try {
          _check(ticket);
          return original;
        } catch (_) {
          original.fillRange(0, original.length, 0);
          rethrow;
        }
      } on ChatLocalMediaException catch (error) {
        if (!const {
          'source_unavailable',
          'source_permission_denied',
          'source_changed',
          'source_corrupt',
          'size_limit',
        }.contains(error.code)) {
          rethrow;
        }
        debugPrint('Chat sent source fallback reason=${error.code}');
      }
    }
    if (await diskCache.wasMoved(ticket.diskKey)) {
      throw const ChatLocalMediaException(
        'local_media_moved',
        'This attachment was moved to the vault. Open it from the vault.',
      );
    }
    final encrypted =
        await diskCache.read(ticket.diskKey) ??
        await downloads?.readCompleted(uid, path);
    _check(ticket);
    if (encrypted == null) {
      throw const ChatLocalMediaException(
        'source_unavailable',
        'The original file and encrypted sent copy are unavailable. Reselect the original file; sent attachments are not downloaded.',
      );
    }
    final plain = await cryptoService.decryptMedia(
      threadId: threadId,
      encryptedBytes: encrypted,
    );
    try {
      _check(ticket);
      if (metadata == null) {
        await localMedia!.put(
          uid: uid,
          path: path,
          direction: ChatMediaDirection.sent,
          ciphertext: encrypted,
        );
      }
      _check(ticket);
      return plain;
    } catch (_) {
      plain.fillRange(0, plain.length, 0);
      rethrow;
    }
  }

  void _check(_LoadTicket ticket) {
    if (_disposed ||
        !ticket.active ||
        ticket.generation != _generation ||
        ticket.pathEpoch != (_pathEpoch[ticket.path] ?? 0)) {
      throw const ChatMediaLoadCancelled();
    }
  }

  _LoadTicket _ticket(String path) =>
      _LoadTicket(_generation, diskKey(path), path, _pathEpoch[path] ?? 0);

  /// Cancels only the loads of one attachment, leaving every other tile alone.
  void _fencePath(String path) {
    _pathEpoch[path] = (_pathEpoch[path] ?? 0) + 1;
    _inFlight.removeWhere((key, _) => key.contains(':$path:'));
    _stages.remove(path);
    _failures.remove(path);
  }

  void _stage(String path, String value) {
    // Stage text is read on rebuild only; notifying here never returned on
    // device and stalled every download after cache-read.
    _stages[path] = value;
  }

  Future<Uint8List> _acquireCiphertext(
    String thread,
    String path,
    _LoadTicket ticket,
    String? senderId,
  ) async {
    try {
      return downloads == null
          ? await mediaRepository.downloadEncryptedMedia(path)
          : await downloads!.acquire(
              uid: _accountId,
              threadId: thread,
              storagePath: path,
              senderId: senderId,
            );
    } on ChatDownloadCancelled {
      // An account/session flip is transient for the tile: re-request.
      throw const ChatMediaLoadCancelled();
    }
  }

  Future<Uint8List> _download(
    String threadId,
    String storagePath,
    _LoadTicket ticket, {
    required bool cachePlaintext,
    String? senderId,
  }) async {
    diskCache.pin(ticket.diskKey);
    Uint8List? plain;
    var returned = false;
    try {
      if (localMedia != null) {
        if (senderId == null) {
          throw const ChatLocalMediaException(
            'identity_missing',
            'Attachment ownership is unavailable. Reopen the chat.',
          );
        }
        if (senderId != _accountId &&
            await diskCache.wasMoved(ticket.diskKey)) {
          throw const ChatLocalMediaException(
            'local_media_moved',
            'This attachment was moved to the vault. Open it from the vault.',
          );
        }
        if (senderId == _accountId) {
          _stage(storagePath, 'Reading sent attachment…');
          plain = await _loadSent(threadId, storagePath, ticket);
        }
      }
      final acquisition = Stopwatch()..start();
      final cachedCiphertext = plain == null
          ? await diskCache.read(ticket.diskKey)
          : null;
      ChatMediaTimings.record(
        'cache-read',
        acquisition,
        bytes: cachedCiphertext?.length,
        cacheHit: cachedCiphertext != null,
      );
      _check(ticket);
      if (cachedCiphertext != null) {
        try {
          _stage(storagePath, 'Authenticating attachment…');
          final decrypt = Stopwatch()..start();
          plain = await cryptoService.decryptMedia(
            threadId: threadId,
            encryptedBytes: cachedCiphertext,
          );
          ChatMediaTimings.record(
            'authenticate-cache',
            decrypt,
            bytes: cachedCiphertext.length,
          );
          if (localMedia != null &&
              await localMedia!.metadata(_accountId, storagePath) == null) {
            _check(ticket);
            await diskCache.write(ticket.diskKey, cachedCiphertext);
          }
        } on SecretBoxAuthenticationError {
          if (localMedia != null) rethrow;
          await diskCache.remove(ticket.diskKey);
        } on FormatException {
          if (localMedia != null) rethrow;
          await diskCache.remove(ticket.diskKey);
        } on RangeError {
          if (localMedia != null) rethrow;
          await diskCache.remove(ticket.diskKey);
        }
      }
      if (plain == null) {
        _stage(storagePath, 'Downloading attachment…');
        final download = Stopwatch()..start();
        final encrypted = await _acquireCiphertext(
          threadId,
          storagePath,
          ticket,
          senderId,
        );
        ChatMediaTimings.record(
          'acquisition',
          download,
          bytes: encrypted.length,
        );
        _check(ticket);
        if (localMedia != null && await diskCache.wasMoved(ticket.diskKey)) {
          throw const ChatLocalMediaException(
            'local_media_moved',
            'This attachment was moved to the vault. Open it from the vault.',
          );
        }
        if (encrypted.isEmpty) {
          throw const FormatException('Attachment is empty or unavailable.');
        }
        _stage(storagePath, 'Authenticating attachment…');
        final decrypt = Stopwatch()..start();
        try {
          plain = await cryptoService.decryptMedia(
            threadId: threadId,
            encryptedBytes: encrypted,
          );
        } on SecretBoxAuthenticationError {
          await downloads?.command(storagePath, 'cancel');
          rethrow;
        } on FormatException {
          await downloads?.command(storagePath, 'cancel');
          rethrow;
        }
        ChatMediaTimings.record(
          'authenticate-download',
          decrypt,
          bytes: encrypted.length,
        );
        _check(ticket);
        try {
          await diskCache.write(ticket.diskKey, encrypted);
          if (!await diskCache.wasMoved(ticket.diskKey)) {
            _check(ticket);
            await downloads?.acknowledge(_accountId, storagePath);
          }
        } on ChatCacheCapacityException {
          debugPrint(
            'Attachment displayed without persistent caching: cache full.',
          );
        } on FileSystemException {
          debugPrint(
            'Attachment displayed without persistent caching: storage unavailable.',
          );
        }
      }
      _check(ticket);
      _stage(storagePath, 'Preparing attachment…');
      _check(ticket);
      if (plain.isEmpty) throw const FormatException('Attachment is empty.');
      if (!cachePlaintext) {
        returned = true;
        return plain;
      }
      seed(storagePath, plain);
      _check(ticket);
      final owned = cached(storagePath);
      if (owned != null) return owned;
      returned = true;
      return plain;
    } on SecretBoxAuthenticationError {
      if (localMedia == null) rethrow;
      final error = ChatLocalMediaException(
        'local_media_corrupt',
        senderId == _accountId
            ? 'The encrypted sent copy cannot be authenticated. Reselect the original file.'
            : 'The encrypted attachment cannot be authenticated. Retry to download a fresh copy.',
      );
      _failures[storagePath] = error;
      throw error;
    } on ChatLocalMediaException catch (error) {
      _failures[storagePath] = error;
      rethrow;
    } finally {
      if (!returned) plain?.fillRange(0, plain.length, 0);
      diskCache.unpin(ticket.diskKey);
    }
  }

  Future<Uint8List> fetchUncached({
    required String threadId,
    required String storagePath,
    String? senderId,
  }) {
    if (localMedia != null && senderId == _accountId) {
      _sentPaths.add(storagePath);
    }
    final ticket = _ticket(storagePath);
    final download = _download(
      threadId,
      storagePath,
      ticket,
      cachePlaintext: false,
      senderId: senderId,
    );
    return (downloads == null
            ? download.timeout(
                loadTimeout,
                onTimeout: () {
                  ticket.active = false;
                  throw TimeoutException(
                    'Attachment download timed out.',
                    loadTimeout,
                  );
                },
              )
            : download)
        .whenComplete(() => ticket.active = false);
  }

  Future<void> removeAfterVaultMove(String storagePath) async {
    await diskCache.markMoved(diskKey(storagePath));
    final removed = _cache.remove(storagePath);
    if (removed != null) {
      _memoryBytes -= removed.length;
      removed.fillRange(0, removed.length, 0);
    }

    // Fence only this attachment's loaders that would publish old bytes.
    _fencePath(storagePath);
    if (!_disposed) notifyListeners();
  }

  /// Vault lock only zeroes plaintext. In-flight downloads keep running, so
  /// one lock does not cancel every visible tile at once.
  void lockPlaintext() {
    for (final bytes in _cache.values) {
      bytes.fillRange(0, bytes.length, 0);
    }
    _cache.clear();
    _memoryBytes = 0;
    if (!_disposed) notifyListeners();
  }

  void clear({String reason = 'unspecified'}) {
    _generation++;
    _scheduler.cancelAll();
    _pathEpoch.clear();
    for (final bytes in _cache.values) {
      bytes.fillRange(0, bytes.length, 0);
    }
    _cache.clear();
    _memoryBytes = 0;
    _sentPaths.clear();
    _inFlight.clear();
    _stages.clear();
    _failures.clear();
    if (!_disposed) notifyListeners();
  }

  Future<void> removeLocal(String storagePath) async {
    _fencePath(storagePath);
    if (downloads != null) await downloads!.command(storagePath, 'cancel');
    await diskCache.remove(diskKey(storagePath));
    final removed = _cache.remove(storagePath);
    if (removed != null) {
      _memoryBytes -= removed.length;
      removed.fillRange(0, removed.length, 0);
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> clearAll() async {
    clear();
    await diskCache.clear();
  }

  @override
  void dispose() {
    clear();
    _disposed = true;
    super.dispose();
  }
}

void _log(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

class _LoadTicket {
  _LoadTicket(this.generation, this.diskKey, this.path, this.pathEpoch);
  final int generation;
  final String diskKey;
  final String path;
  final int pathEpoch;
  bool active = true;
}

class _MediaAcquisition {
  _MediaAcquisition(this.future, this.generation, this.task);
  final Future<Uint8List> future;
  final int generation;
  final _MediaTask task;
  int consumers = 0;
  int waiting = 0;
}

/// Lets a tile withdraw interest when it is disposed or scrolled away.
class ChatMediaLoadToken {
  VoidCallback? _release;
  bool _cancelled = false;

  void _attach(VoidCallback release) {
    if (_cancelled) {
      release();
    } else {
      _release = release;
    }
  }

  void cancel() {
    _cancelled = true;
    final release = _release;
    _release = null;
    release?.call();
  }
}

class _MediaTask {
  _MediaTask(this.run, this.order);
  final Future<Uint8List> Function() run;
  final Completer<Uint8List> _completer = Completer<Uint8List>();
  int order;
  bool started = false;
  Future<Uint8List> get future => _completer.future;
}

/// Bounded parallelism, most recently requested first: the newest request is
/// the tile that just scrolled into view.
class _MediaScheduler {
  _MediaScheduler(this.maxConcurrent);
  final int maxConcurrent;
  final List<_MediaTask> _queue = [];
  int _running = 0;
  int _order = 0;

  _MediaTask submit(Future<Uint8List> Function() run) {
    final task = _MediaTask(run, ++_order);
    _queue.add(task);
    _pump();
    return task;
  }

  void promote(_MediaTask task) => task.order = ++_order;

  void cancelQueued(_MediaTask task) {
    if (task.started || !_queue.remove(task)) return;
    task._completer.completeError(const ChatMediaLoadCancelled());
  }

  void cancelAll() {
    for (final task in List.of(_queue)) {
      cancelQueued(task);
    }
  }

  void _pump() {
    while (_running < maxConcurrent && _queue.isNotEmpty) {
      var next = _queue.first;
      for (final task in _queue) {
        if (task.order > next.order) next = task;
      }
      _queue.remove(next);
      next.started = true;
      _running++;
      Future<Uint8List>.sync(next.run)
          .then(
            next._completer.complete,
            onError: next._completer.completeError,
          )
          .whenComplete(() {
            _running--;
            _pump();
          });
    }
  }
}

class ChatMediaLoadCancelled implements Exception {
  const ChatMediaLoadCancelled();
  @override
  String toString() => 'Attachment request was cancelled.';
}
