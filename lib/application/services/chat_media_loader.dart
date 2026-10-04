import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../crypto/services/chat_crypto_service.dart';
import '../../domain/repositories/message_repository.dart';
import 'chat_media_cache.dart';

/// Shared, observable attachment decryption with bounded plaintext memory.
class ChatMediaLoader extends ChangeNotifier {
  ChatMediaLoader({
    required this.mediaRepository,
    required this.cryptoService,
    ChatMediaCache? diskCache,
    this.maxMemoryBytes = 32 * 1024 * 1024,
    this.loadTimeout = const Duration(seconds: 45),
    String accountId = '',
  }) : diskCache = diskCache ?? ChatMediaCache(),
       _accountId = accountId;

  final MediaRepository mediaRepository;
  final ChatCryptoService cryptoService;
  final ChatMediaCache diskCache;
  final int maxMemoryBytes;
  final Duration loadTimeout;
  final Map<String, Uint8List> _cache = {};
  final Map<String, Future<Uint8List>> _inFlight = {};
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
    return bytes;
  }

  void seed(String storagePath, Uint8List bytes) {
    if (_disposed || bytes.isEmpty || bytes.length > maxMemoryBytes) return;
    final old = _cache.remove(storagePath);
    if (old != null) _memoryBytes -= old.length;
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
  }) {
    final hit = cached(storagePath);
    if (hit != null) return Future.value(hit);
    final key = '$threadId:$storagePath';
    final running = _inFlight[key];
    if (running != null) return running;
    final ticket = _LoadTicket(_generation, diskKey(storagePath));
    late final Future<Uint8List> future;
    future = _download(threadId, storagePath, ticket, cachePlaintext: true)
        .timeout(
          loadTimeout,
          onTimeout: () {
            ticket.active = false;
            throw TimeoutException(
              'Attachment download timed out.',
              loadTimeout,
            );
          },
        )
        .whenComplete(() {
          ticket.active = false;
          if (identical(_inFlight[key], future)) _inFlight.remove(key);
        });
    _inFlight[key] = future;
    return future;
  }

  void _check(_LoadTicket ticket) {
    if (_disposed || !ticket.active || ticket.generation != _generation) {
      throw const ChatMediaLoadCancelled();
    }
  }

  Future<Uint8List> _download(
    String threadId,
    String storagePath,
    _LoadTicket ticket, {
    required bool cachePlaintext,
  }) async {
    final cachedCiphertext = await diskCache.read(ticket.diskKey);
    _check(ticket);
    Uint8List? plain;
    if (cachedCiphertext != null) {
      try {
        plain = await cryptoService.decryptMedia(
          threadId: threadId,
          encryptedBytes: cachedCiphertext,
        );
      } on SecretBoxAuthenticationError {
        await diskCache.remove(ticket.diskKey);
      } on FormatException {
        await diskCache.remove(ticket.diskKey);
      } on RangeError {
        await diskCache.remove(ticket.diskKey);
      }
    }
    if (plain == null) {
      final encrypted = await mediaRepository.downloadEncryptedMedia(
        storagePath,
      );
      _check(ticket);
      if (encrypted.isEmpty) {
        throw const FormatException('Attachment is empty or unavailable.');
      }
      // Authenticate before caching, so a bad remote object never poisons disk.
      plain = await cryptoService.decryptMedia(
        threadId: threadId,
        encryptedBytes: encrypted,
      );
      _check(ticket);
      try {
        await diskCache.write(ticket.diskKey, encrypted);
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
    if (plain.isEmpty) throw const FormatException('Attachment is empty.');
    if (!cachePlaintext) return plain;
    seed(storagePath, plain);
    final owned = cached(storagePath);
    if (owned != null) {
      plain.fillRange(0, plain.length, 0);
      return owned;
    }
    return plain;
  }

  Future<Uint8List> fetchUncached({
    required String threadId,
    required String storagePath,
  }) {
    final ticket = _LoadTicket(_generation, diskKey(storagePath));
    return _download(threadId, storagePath, ticket, cachePlaintext: false)
        .timeout(
          loadTimeout,
          onTimeout: () {
            ticket.active = false;
            throw TimeoutException(
              'Attachment download timed out.',
              loadTimeout,
            );
          },
        )
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
    if (!_disposed) notifyListeners();
  }

  void clear() {
    _generation++;
    for (final bytes in _cache.values) {
      bytes.fillRange(0, bytes.length, 0);
    }
    _cache.clear();
    _memoryBytes = 0;
    _inFlight.clear();
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

class ChatMediaLoadCancelled implements Exception {
  const ChatMediaLoadCancelled();
  @override
  String toString() => 'Attachment request was cancelled.';
}
