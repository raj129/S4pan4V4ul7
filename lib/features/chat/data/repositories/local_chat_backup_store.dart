import 'dart:io';
import 'dart:typed_data';

import 'package:external_path/external_path.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:photo_vault/features/vault/application/services/vault_storage_root.dart';
import '../../domain/repositories/chat_backup_store.dart';

/// Keeps the chat backup on this device, where it survives "Clear app data".
///
/// Writes go to an app-owned Android/media folder, which needs no storage
/// permission on Android 11+. Older builds wrote to public Documents, which
/// scoped storage blocks, so reads and deletes also check that location.
class LocalChatBackupStore implements ChatBackupStore {
  LocalChatBackupStore({
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
  bool get requiresNetwork => false;

  @override
  bool get isCloud => false;

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

  /// Legacy folder for reads and deletes only. Access errors are ignored.
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

  String _fileName(String accountId) => 'chat_backup_$accountId.enc';

  @override
  Future<void> write(
    String accountId,
    Uint8List blob, {
    bool interactive = false,
  }) async {
    final file = File(p.join((await _folder()).path, _fileName(accountId)));
    // Write-then-rename so a crash mid-write never leaves a torn backup.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(blob, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  @override
  Future<void> delete(String accountId, {bool interactive = false}) async {
    final dirs = [await _folder(), ?await _legacyFolder()];
    for (final dir in dirs) {
      final file = File(p.join(dir.path, _fileName(accountId)));
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<Uint8List?> read(String accountId, {bool interactive = false}) async {
    final primary = File(p.join((await _folder()).path, _fileName(accountId)));
    if (await primary.exists()) return primary.readAsBytes();
    final legacy = await _legacyFolder();
    if (legacy == null) return null;
    final old = File(p.join(legacy.path, _fileName(accountId)));
    if (!await old.exists()) return null;
    return old.readAsBytes();
  }
}
