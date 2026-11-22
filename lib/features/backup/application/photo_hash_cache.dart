import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// SHA-256 cache for vault ciphertext, so the nightly run does not re-read
/// every photo. An entry is reused only while the file's size and modified
/// time are unchanged; any change forces a fresh hash.
class PhotoHashCache {
  PhotoHashCache({required Future<File> Function() file}) : _file = file;

  final Future<File> Function() _file;
  Map<String, String> _entries = {};
  final Set<String> _used = {};

  Future<void> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map) {
        _entries = {
          for (final e in decoded.entries) e.key as String: e.value as String,
        };
      }
    } catch (_) {
      // A damaged cache is only a performance loss; start empty.
      _entries = {};
    }
  }

  /// SHA-256 of [file], from cache when [key] and the file metadata match.
  /// Returns null when the file does not exist.
  Future<String?> hashOf(String key, File file) async {
    if (!await file.exists()) return null;
    final stat = await file.stat();
    final stamp = '$key|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    _used.add(stamp);
    final cached = _entries[stamp];
    if (cached != null) return cached;
    final digest = await hash.sha256.bind(file.openRead()).first;
    final value = digest.toString();
    _entries[stamp] = value;
    return value;
  }

  /// Persists only entries used in the latest run, so the cache cannot grow
  /// with deleted photos.
  Future<void> save() async {
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final kept = {
        for (final key in _used)
          if (_entries[key] != null) key: _entries[key]!,
      };
      await file.writeAsString(jsonEncode(kept), flush: true);
      _entries = kept;
    } catch (_) {
      // Losing the cache only costs time on the next run.
    }
  }

  static Future<File> _defaultCacheFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'backup_hash_cache.json'));
  }

  /// Cache stored in app-private support storage (shared by app and nightly).
  factory PhotoHashCache.defaults() => PhotoHashCache(file: _defaultCacheFile);
}
