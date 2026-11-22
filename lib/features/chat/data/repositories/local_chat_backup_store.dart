import 'dart:io';
import 'dart:typed_data';

import 'package:photo_vault/features/backup/data/local_backup_blob_store.dart';
import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import '../../domain/repositories/chat_backup_store.dart';

/// Keeps the chat backup on this device, where it survives "Clear app data".
///
/// Delegates to [LocalBackupBlobStore] so chat backups share the exact same
/// `Android/media` recovery folder, legacy `Documents` fallback, and atomic
/// `.tmp` writes as vault photo and VMK backups.
class LocalChatBackupStore implements ChatBackupStore {
  LocalChatBackupStore({
    Future<Directory> Function()? baseDirectory,
    Future<Directory?> Function()? legacyDirectory,
    BackupByteStore? store,
  }) : _store =
           store ??
           LocalBackupBlobStore(
             baseDirectory: baseDirectory,
             legacyDirectory: legacyDirectory,
           );

  final BackupByteStore _store;

  @override
  String get label => _store.label;

  @override
  bool get requiresNetwork => _store.requiresNetwork;

  @override
  bool get isCloud => _store.isCloud;

  static String _fileName(String accountId) => 'chat_backup_$accountId.enc';

  @override
  Future<void> write(
    String accountId,
    Uint8List blob, {
    bool interactive = false,
  }) => _store.writeBytes(
    _fileName(accountId),
    blob,
    interactive: interactive,
  );

  @override
  Future<void> delete(String accountId, {bool interactive = false}) =>
      _store.delete(_fileName(accountId), interactive: interactive);

  @override
  Future<Uint8List?> read(String accountId, {bool interactive = false}) =>
      _store.readBytes(_fileName(accountId), interactive: interactive);
}
