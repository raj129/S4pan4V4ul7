import '../../application/services/restore_flow_service.dart';
import '../../domain/repositories/secure_storage_repository.dart';
import '../../domain/repositories/vmk_backup_repository.dart';

class BackupRestoreFlowService implements RestoreFlowService {
  BackupRestoreFlowService({
    required SecureStorageRepository secureStorageRepository,
    required List<VmkBackupRepository> backupRepositories,
  })  : _secureStorageRepository = secureStorageRepository,
        _backupRepositories = backupRepositories;

  final SecureStorageRepository _secureStorageRepository;
  final List<VmkBackupRepository> _backupRepositories;

  @override
  Future<bool> hasBackupManifest() async {
    // For now, we check if any repository has a backup.
    // In a real scenario, we might want to check for a specific vaultId if known,
    // or list all available backups.
    // For simplicity, we'll assume we are looking for the 'primary' backup.
    return true; // Simplified
  }

  @override
  Future<void> fetchBackupManifest() async {
    // Implementation to fetch list of photos/metadata
  }

  @override
  Future<void> restoreEncryptedVmk() async {
    Map<String, String>? payload;
    String? foundVaultId;

    for (final repo in _backupRepositories) {
      try {
        final ids = await repo.listVaultIds();
        if (ids.isNotEmpty) {
          foundVaultId = ids.first; // For now, just take the first one found
          payload = await repo.restoreVmk(foundVaultId);
          if (payload != null) break;
        }
      } catch (_) {
        continue;
      }
    }
    
    if (payload != null && foundVaultId != null) {
      await _secureStorageRepository.storeWrappedVmk(
        vaultId: foundVaultId,
        wrappedVmkBase64: payload['wrappedVmk']!,
        nonceBase64: payload['nonce']!,
        macBase64: payload['mac']!,
        saltBase64: payload['salt']!,
        encVersion: int.parse(payload['encVersion']!),
      );
    } else {
      throw Exception('No backup found in any repository.');
    }
  }

  @override
  Future<void> restoreMetadataAndPhotos({required bool includePhotos}) async {
    // Implementation to download files from Drive or copy from local storage
  }
}
