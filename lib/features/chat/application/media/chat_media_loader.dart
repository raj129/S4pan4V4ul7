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
    String accountId = '',
    this.downloads,
    this.localMedia,
  }) : diskCache = diskCache ?? ChatMediaCache(),
       _accountId = accountId;

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
  String _accountId;
  int _generation = 0;
  int _memoryBytes = 0;
  bool _disposed = false;

  String get accountId => _accountId;
  String diskKey(String storagePath) => '$_accountId:$storagePath';

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
  }) {
    if (localMedia != null && senderId == _accountId) {
      _sentPaths.add(storagePath);
    }
    final hit = cached(storagePath);
    if (hit != null) return Future.value(hit);
    final key = '$threadId:$storagePath:$senderId';
    final running = _inFlight[key];
    if (running != null) return _own(running);
    final ticket = _LoadTicket(_generation, diskKey(storagePath));
    late final Future<Uint8List> future;
    final download = _download(
      threadId,
      storagePath,
      ticket,
      cachePlaintext: true,
      senderId: senderId,
    );
    future =
        (downloads == null
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
            .whenComplete(() {
              ticket.active = false;
              if (identical(_inFlight[key]?.future, future)) {
                _inFlight.remove(key);
              }
            });
    final acquisition = _MediaAcquisition(future, _generation);
    _inFlight[key] = acquisition;
    return _own(acquisition);
  }

  Future<Uint8List> _own(_MediaAcquisition acquisition) async {
    acquisition.consumers++;
    Uint8List? source;
    try {
      source = await acquisition.future;
      if (_disposed || acquisition.generation != _generation) {
        throw const ChatMediaLoadCancelled();
      }
      return Uint8List.fromList(source);
    } finally {
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
    if (_disposed || !ticket.active || ticket.generation != _generation) {
      throw const ChatMediaLoadCancelled();
    }
  }

  void _stage(String path, String value) {
    _stages[path] = value;
    if (!_disposed && downloads != null) notifyListeners();
  }

  Future<Uint8List> _acquireCiphertext(
    String thread,
    String path,
    _LoadTicket ticket,
    String? senderId,
  ) async {
    return downloads == null
        ? mediaRepository.downloadEncryptedMedia(path)
        : downloads!.acquire(
            uid: _accountId,
            threadId: thread,
            storagePath: path,
            senderId: senderId,
          );
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
    final ticket = _LoadTicket(_generation, diskKey(storagePath));
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

    // Fence any outstanding loader that would otherwise publish old bytes.
    _generation++;
    _inFlight.clear();
    _stages.clear();
    _failures.clear();
    if (!_disposed) notifyListeners();
  }

  void clear() {
    _generation++;
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
    _generation++;
    _inFlight.clear();
    if (downloads != null) await downloads!.command(storagePath, 'cancel');
    await diskCache.remove(diskKey(storagePath));
    final removed = _cache.remove(storagePath);
    if (removed != null) {
      _memoryBytes -= removed.length;
      removed.fillRange(0, removed.length, 0);
    }
    _stages.remove(storagePath);
    _failures.remove(storagePath);
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

class _LoadTicket {
  _LoadTicket(this.generation, this.diskKey);
  final int generation;
  final String diskKey;
  bool active = true;
}

class _MediaAcquisition {
  _MediaAcquisition(this.future, this.generation);
  final Future<Uint8List> future;
  final int generation;
  int consumers = 0;
}

class ChatMediaLoadCancelled implements Exception {
  const ChatMediaLoadCancelled();
  @override
  String toString() => 'Attachment request was cancelled.';
}
