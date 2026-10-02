import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

abstract interface class AttachmentStagingStore {
  Future<void> writeMedia(String messageId, Uint8List encryptedBytes);
  Future<void> writeThumbnail(String messageId, Uint8List encryptedBytes);
  Future<Uint8List?> readMedia(String messageId);
  Future<Uint8List?> readThumbnail(String messageId);
  Future<void> deleteMedia(String messageId);
  Future<void> deleteThumbnail(String messageId);
  Future<void> cleanOrphans(Set<String> activeMessageIds);
}

/// Persists only encrypted attachment bytes in app-private support storage.
class FileAttachmentStagingStore implements AttachmentStagingStore {
  FileAttachmentStagingStore({Directory? directory}) : _directory = directory;

  static const _directoryName = 'chat_media_outbox';
  static const _maxBytes = 512 * 1024 * 1024;
  Directory? _directory;
  Future<Directory>? _pendingDirectory;

  Future<Directory> _dir() {
    final ready = _directory;
    if (ready != null) return Future.value(ready);
    return _pendingDirectory ??= _createDirectory();
  }

  Future<Directory> _createDirectory() async {
    final base = await getApplicationSupportDirectory();
    final directory = Directory(p.join(base.path, _directoryName));
    await directory.create(recursive: true);
    _directory = directory;
    return directory;
  }

  String _filename(String messageId, String kind) =>
      '${sha256.convert(utf8.encode(messageId)).toString()}.$kind.enc';

  Future<File> _file(String messageId, String kind) async =>
      File(p.join((await _dir()).path, _filename(messageId, kind)));

  Future<void> _write(
    String messageId,
    String kind,
    Uint8List encryptedBytes,
  ) async {
    if (encryptedBytes.isEmpty) {
      throw ArgumentError.value(
        encryptedBytes,
        'encryptedBytes',
        'must not be empty',
      );
    }
    final file = await _file(messageId, kind);
    final directory = await _dir();
    var totalBytes = 0;
    await for (final entry in directory.list()) {
      if (entry is File && entry.path != file.path) {
        totalBytes += await entry.length();
      }
    }
    if (totalBytes + encryptedBytes.length > _maxBytes) {
      throw FileSystemException(
        'The pending attachment storage limit has been reached.',
        directory.path,
      );
    }

    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(encryptedBytes, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<Uint8List?> _read(String messageId, String kind) async {
    final file = await _file(messageId, kind);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  }

  Future<void> _delete(String messageId, String kind) async {
    final file = await _file(messageId, kind);
    if (await file.exists()) await file.delete();
    final temporary = File('${file.path}.tmp');
    if (await temporary.exists()) await temporary.delete();
  }

  @override
  Future<void> cleanOrphans(Set<String> activeMessageIds) async {
    final directory = await _dir();
    final activeFiles = {
      for (final id in activeMessageIds) _filename(id, 'media'),
      for (final id in activeMessageIds) _filename(id, 'thumb'),
    };
    await for (final entry in directory.list()) {
      if (entry is File && !activeFiles.contains(p.basename(entry.path))) {
        await entry.delete();
      }
    }
  }

  @override
  Future<void> writeMedia(String messageId, Uint8List encryptedBytes) =>
      _write(messageId, 'media', encryptedBytes);

  @override
  Future<void> writeThumbnail(String messageId, Uint8List encryptedBytes) =>
      _write(messageId, 'thumb', encryptedBytes);

  @override
  Future<Uint8List?> readMedia(String messageId) => _read(messageId, 'media');

  @override
  Future<Uint8List?> readThumbnail(String messageId) =>
      _read(messageId, 'thumb');

  @override
  Future<void> deleteMedia(String messageId) => _delete(messageId, 'media');

  @override
  Future<void> deleteThumbnail(String messageId) => _delete(messageId, 'thumb');
}

/// In-memory staging for isolated unit tests and non-persistent test wiring.
class MemoryAttachmentStagingStore implements AttachmentStagingStore {
  final Map<String, Uint8List> _media = {};
  final Map<String, Uint8List> _thumbnails = {};

  @override
  Future<void> writeMedia(String messageId, Uint8List encryptedBytes) async {
    _media[messageId] = Uint8List.fromList(encryptedBytes);
  }

  @override
  Future<void> writeThumbnail(
    String messageId,
    Uint8List encryptedBytes,
  ) async {
    _thumbnails[messageId] = Uint8List.fromList(encryptedBytes);
  }

  @override
  Future<Uint8List?> readMedia(String messageId) async =>
      _media[messageId] == null ? null : Uint8List.fromList(_media[messageId]!);

  @override
  Future<Uint8List?> readThumbnail(String messageId) async =>
      _thumbnails[messageId] == null
      ? null
      : Uint8List.fromList(_thumbnails[messageId]!);

  @override
  Future<void> deleteMedia(String messageId) async {
    _media.remove(messageId);
  }

  @override
  Future<void> deleteThumbnail(String messageId) async {
    _thumbnails.remove(messageId);
  }

  @override
  Future<void> cleanOrphans(Set<String> activeMessageIds) async {
    _media.removeWhere((messageId, _) => !activeMessageIds.contains(messageId));
    _thumbnails.removeWhere(
      (messageId, _) => !activeMessageIds.contains(messageId),
    );
  }
}
