import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/features/backup/data/drive_backup_blob_store.dart';
import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import 'blob_vmk_backup_repository.dart';

/// Persists wrapped VMK envelopes in Google Drive `appDataFolder`.
///
/// Delegates to [DriveBackupBlobStore] so queries exclude trashed files, pick
/// the newest copy, clean up duplicate entries, and validate JSON safely.
class GoogleDriveVmkRepository extends BlobVmkBackupRepository {
  GoogleDriveVmkRepository({
    required AuthRepository authRepository,
    BackupByteStore? store,
  }) : super(
         store: store ?? DriveBackupBlobStore(authRepository: authRepository),
         fileName: _fileName,
       );

  static const String _fileName = 'vmk_backup.json';
}
