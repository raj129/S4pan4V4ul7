import 'dart:io';

import 'package:photo_vault/features/backup/data/local_backup_blob_store.dart';
import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import 'blob_vmk_backup_repository.dart';

/// Persists wrapped VMK envelopes locally so they survive app-data clears.
///
/// Delegates to [LocalBackupBlobStore] so Android 11+ scoped storage uses the
/// app-owned `Android/media/<pkg>/PhotoVault_Recovery` folder (with read-only
/// fallback to legacy public `Documents`), desktop uses `ApplicationDocuments`,
/// and writes are atomic via `.tmp` rename.
class LocalVmkBackupRepository extends BlobVmkBackupRepository {
  LocalVmkBackupRepository({
    Future<Directory> Function()? baseDirectory,
    Future<Directory?> Function()? legacyDirectory,
    BackupByteStore? store,
  }) : super(
         store:
             store ??
             LocalBackupBlobStore(
               baseDirectory: baseDirectory,
               legacyDirectory: legacyDirectory,
             ),
         fileName: _fileName,
       );

  static const String _fileName = 'vmk_recovery.json';
}
