import 'dart:typed_data';

import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/features/backup/data/drive_backup_blob_store.dart';
import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import '../../domain/repositories/chat_backup_store.dart';

/// Keeps the chat backup in the user's Google Drive app-data folder, which is
/// private to this app and survives uninstalling or clearing data.
///
/// Delegates to [DriveBackupBlobStore] so Drive queries exclude trashed files,
/// pick the newest copy, and clean up duplicate entries.
class GoogleDriveChatBackupStore implements ChatBackupStore {
  GoogleDriveChatBackupStore({
    required AuthRepository authRepository,
    BackupByteStore? store,
  }) : _store = store ?? DriveBackupBlobStore(authRepository: authRepository);

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
