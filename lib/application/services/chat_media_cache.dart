import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// An account-scoped ciphertext cache. Callers include the account in the key.
class ChatMediaCache {
  ChatMediaCache({Directory? directory, this.maxBytes = 150 * 1024 * 1024})
    : _directory = directory;

  final int maxBytes;
  Directory? _directory;
  Future<Directory>? _pending;
  Future<void> _writes = Future<void>.value();
  final Set<String> _pinned = {};

  Future<Directory> _dir() => _pending ??= _create();

  Future<Directory> _create() async {
    final base = _directory;
    final dir =
        base ??
        Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'chat_media_cache',
          ),
        );
    await dir.create(recursive: true);
    _directory = dir;
    return dir;
  }

  String _key(String storagePath) =>
      crypto.sha256.convert(utf8.encode(storagePath)).toString();

  Future<File> _fileFor(String storagePath) async =>
      File(p.join((await _dir()).path, _key(storagePath)));

  Future<bool> wasMoved(String storagePath) async =>
      File('${(await _fileFor(storagePath)).path}.moved').exists();

  void pin(String storagePath) => _pinned.add(_key(storagePath));
  void unpin(String storagePath) => _pinned.remove(_key(storagePath));

  Future<Uint8List?> read(String storagePath) async {
    final file = await _fileFor(storagePath);
    try {
      if (await wasMoved(storagePath)) return null;
      if (!await file.exists()) return null;
      if (await file.length() > 64 * 1024 * 1024) {
        await file.delete();
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      await file.setLastModified(DateTime.now());
      return bytes;
    } on FileSystemException {
      debugPrint('Chat ciphertext cache read unavailable.');
      return null;
    }
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final result = _writes.then((_) => action());
    // The caller receives the failure; a failed operation must not poison
    // every subsequent cache operation.
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> write(String storagePath, Uint8List encryptedBytes) =>
      _serialize(() async {
        if (encryptedBytes.isEmpty || encryptedBytes.length > maxBytes) {
          throw const ChatCacheCapacityException();
        }
        if (await wasMoved(storagePath)) return;
        final file = await _fileFor(storagePath);
        final temp = File('${file.path}.${const Uuid().v4()}.part');
        try {
          await temp.writeAsBytes(encryptedBytes, flush: true);
          // A background isolate may have recorded a move during the write.
          if (await wasMoved(storagePath)) return;
          await temp.rename(file.path);
          if (await wasMoved(storagePath)) {
            await remove(storagePath);
            return;
          }
          await _evictIfNeeded();
        } finally {
          if (await temp.exists()) await temp.delete();
        }
      });

  Future<void> remove(String storagePath) async {
    final file = await _fileFor(storagePath);
    if (await file.exists()) await file.delete();
  }

  /// The marker precedes deletion: a crash cannot trigger a new full download.
  /// Only call after the vault has durably committed the imported attachment.
  Future<void> markMoved(String storagePath) => _serialize(() async {
    final file = await _fileFor(storagePath);
    await File('${file.path}.moved').writeAsString('1', flush: true);
    await remove(storagePath);
  });

  Future<void> _evictIfNeeded() async {
    final files = <(File, FileStat)>[];
    var total = 0;
    await for (final entity in (await _dir()).list()) {
      if (entity is! File ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(p.basename(entity.path))) {
        continue;
      }
      try {
        final stat = await entity.stat();
        if (stat.type != FileSystemEntityType.file) continue;
        total += stat.size;
        files.add((entity, stat));
      } on FileSystemException {
        debugPrint('Chat cache entry changed during eviction.');
      }
    }
    files.sort((a, b) => a.$2.modified.compareTo(b.$2.modified));
    for (final (file, stat) in files) {
      if (total <= maxBytes) break;
      if (_pinned.contains(p.basename(file.path))) continue;
      try {
        await file.delete();
        total -= stat.size;
      } on FileSystemException {
        debugPrint('Chat cache entry could not be evicted.');
      }
    }
    if (total > maxBytes) throw const ChatCacheCapacityException();
  }

  /// Remove ciphertext, but preserve moved markers across sign-out/restarts.
  Future<void> clear() => _serialize(() async {
    await for (final entity in (await _dir()).list()) {
      if (entity is File &&
          RegExp(r'^[0-9a-f]{64}$').hasMatch(p.basename(entity.path))) {
        await entity.delete();
      }
    }
  });
}

class ChatCacheCapacityException implements Exception {
  const ChatCacheCapacityException();

  @override
  String toString() => 'Not enough space in the attachment cache.';
}
