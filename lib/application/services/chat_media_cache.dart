import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// On-disk cache for chat attachments, so a thread does not re-download every
/// image each time the app restarts.
///
/// Only *ciphertext* is cached. The bytes are exactly what Storage returned, so
/// the cache is no more revealing than the bucket itself, and a decrypted photo
/// never reaches the filesystem — the same rule the vault follows.
class ChatMediaCache {
  ChatMediaCache({Directory? directory, this.maxBytes = _defaultMaxBytes})
    : _directory = directory;

  static const _defaultMaxBytes = 150 * 1024 * 1024;
  static const _dirName = 'chat_media_cache';

  /// Eviction ceiling for the whole cache directory.
  final int maxBytes;

  Directory? _directory;
  Future<Directory>? _pending;

  Future<Directory> _dir() {
    final ready = _directory;
    if (ready != null) return Future.value(ready);
    return _pending ??= _create();
  }

  Future<Directory> _create() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory(p.join(base.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    _directory = dir;
    return dir;
  }

  /// Storage paths contain slashes and unbounded IDs, so address files by a
  /// hash instead of trying to sanitise the path.
  String _key(String storagePath) =>
      crypto.sha256.convert(utf8.encode(storagePath)).toString();

  Future<File> _fileFor(String storagePath) async {
    final dir = await _dir();
    return File(p.join(dir.path, _key(storagePath)));
  }

  Future<Uint8List?> read(String storagePath) async {
    try {
      final file = await _fileFor(storagePath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      // Touch so eviction treats this as recently used.
      unawaited(file.setLastModified(DateTime.now()).catchError((_) {}));
      return bytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String storagePath, Uint8List encryptedBytes) async {
    try {
      final file = await _fileFor(storagePath);
      await file.writeAsBytes(encryptedBytes, flush: true);
      await _evictIfNeeded();
    } catch (_) {
      // A cache miss is always survivable; never fail a download over it.
    }
  }

  /// Drops the least recently used entries until the directory fits again.
  Future<void> _evictIfNeeded() async {
    try {
      final dir = await _dir();
      final files = <File>[];
      var total = 0;
      await for (final entity in dir.list()) {
        if (entity is! File) continue;
        files.add(entity);
        total += await entity.length();
      }
      if (total <= maxBytes) return;

      final stamped = <MapEntry<File, DateTime>>[];
      for (final f in files) {
        stamped.add(MapEntry(f, (await f.stat()).modified));
      }
      stamped.sort((a, b) => a.value.compareTo(b.value));
      for (final entry in stamped) {
        if (total <= maxBytes) break;
        total -= await entry.key.length();
        await entry.key.delete();
      }
    } catch (_) {}
  }

  /// Wipes the cache, e.g. on sign-out.
  Future<void> clear() async {
    try {
      final dir = await _dir();
      if (await dir.exists()) await dir.delete(recursive: true);
      // Recreated rather than forgotten: the same instance keeps being used
      // after a sign-out, and the next write must land somewhere.
      await dir.create(recursive: true);
    } catch (_) {}
  }
}
