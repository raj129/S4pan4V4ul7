import 'dart:io';
import 'dart:typed_data';

import 'package:external_path/external_path.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/repositories/chat_backup_store.dart';

/// Keeps the chat backup in a user-visible folder that survives "Clear app
/// data" (public Documents on Android, the Documents folder on desktop).
class LocalChatBackupStore implements ChatBackupStore {
  LocalChatBackupStore({Future<Directory> Function()? baseDirectory})
    : _baseDirectory = baseDirectory ?? _defaultBaseDirectory;

  final Future<Directory> Function() _baseDirectory;

  static const _folderName = 'PhotoVault_Recovery';

  @override
  String get label => 'This device';

  @override
  bool get requiresNetwork => false;

  static Future<Directory> _defaultBaseDirectory() async {
    if (Platform.isAndroid) {
      final docs = await ExternalPath.getExternalStoragePublicDirectory(
        ExternalPath.DIRECTORY_DOCUMENTS,
      );
      return Directory(docs);
    }
    return getApplicationDocumentsDirectory();
  }

  Future<File> _file(String accountId) async {
    final base = await _baseDirectory();
    final dir = Directory(p.join(base.path, _folderName));
    if (!await dir.exists()) await dir.create(recursive: true);
    return File(p.join(dir.path, 'chat_backup_$accountId.enc'));
  }

  @override
  Future<void> write(
    String accountId,
    Uint8List blob, {
    bool interactive = false,
  }) async {
    final file = await _file(accountId);
    // Write-then-rename so a crash mid-write never leaves a torn backup.
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(blob, flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  @override
  Future<Uint8List?> read(
    String accountId, {
    bool interactive = false,
  }) async {
    final file = await _file(accountId);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }
}
