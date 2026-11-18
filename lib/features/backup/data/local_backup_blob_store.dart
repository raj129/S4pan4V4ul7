import 'dart:io';

import 'package:external_path/external_path.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../vault/application/services/vault_storage_root.dart';
import '../domain/backup_blob_store.dart';

/// Keeps blobs on this device so they survive "Clear app data".
///
/// Writes go to an app-owned Android/media folder, which needs no storage
/// permission on Android 11+. Older builds wrote to public Documents, which
/// scoped storage now blocks, so reads also check that location as a
/// read-only fallback. On desktop the primary location is Documents.
class LocalBackupBlobStore implements BackupBlobStore {
  LocalBackupBlobStore({
    Future<Directory> Function()? baseDirectory,
    Future<Directory?> Function()? legacyDirectory,
  }) : _baseDirectory = baseDirectory ?? _defaultBaseDirectory,
       _legacyDirectory = legacyDirectory ?? _defaultLegacyDirectory;

  final Future<Directory> Function() _baseDirectory;
  final Future<Directory?> Function() _legacyDirectory;

  static const _folderName = 'PhotoVault_Recovery';

  @override
  String get label => 'This device';

  @override
  bool get isCloud => false;

  @override
  bool get requiresNetwork => false;

  static Future<Directory> _defaultBaseDirectory() async {
    if (Platform.isAndroid) {
      final media = await resolveAppMediaRoot();
      if (media != null) return media;
    }
    return getApplicationDocumentsDirectory();
  }

  /// Public Documents, where older builds wrote. Null off Android.
  static Future<Directory?> _defaultLegacyDirectory() async {
    if (!Platform.isAndroid) return null;
    final docs = await ExternalPath.getExternalStoragePublicDirectory(
      ExternalPath.DIRECTORY_DOCUMENTS,
    );
    return Directory(docs);
  }

  Future<Directory> _folder() async {
    final base = await _baseDirectory();
    final dir = Directory(p.join(base.path, _folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Folder used only for reads and deletes of blobs written by older builds.
  /// Any access error is ignored: the location may be unreadable.
  Future<Directory?> _legacyFolder() async {
    try {
      final base = await _legacyDirectory();
      if (base == null) return null;
      final dir = Directory(p.join(base.path, _folderName));
      return await dir.exists() ? dir : null;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> writeFile(
    String name,
    File source, {
    bool interactive = false,
  }) async {
    final dir = await _folder();
    final file = File(p.join(dir.path, name));
    // Copy to a temp name, then rename, so a crash mid-copy never leaves a
    // torn blob behind.
    final tmp = File('${file.path}.tmp');
    await source.copy(tmp.path);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  @override
  Future<bool> readToFile(
    String name,
    File destination, {
    bool interactive = false,
  }) async {
    final primary = File(p.join((await _folder()).path, name));
    if (await primary.exists()) {
      await primary.copy(destination.path);
      return true;
    }
    final legacy = await _legacyFolder();
    if (legacy == null) return false;
    final old = File(p.join(legacy.path, name));
    if (!await old.exists()) return false;
    await old.copy(destination.path);
    return true;
  }

  @override
  Future<List<String>> list(String prefix, {bool interactive = false}) async {
    final names = <String>{};
    final dirs = [await _folder(), ?await _legacyFolder()];
    for (final dir in dirs) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith(prefix) && !name.endsWith('.tmp')) names.add(name);
      }
    }
    return names.toList();
  }

  @override
  Future<void> delete(String name, {bool interactive = false}) async {
    final dirs = [await _folder(), ?await _legacyFolder()];
    for (final dir in dirs) {
      final file = File(p.join(dir.path, name));
      if (await file.exists()) await file.delete();
    }
  }
}
