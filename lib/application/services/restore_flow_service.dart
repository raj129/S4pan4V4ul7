abstract class RestoreFlowService {
  Future<bool> hasBackupManifest();
  Future<void> fetchBackupManifest();
  Future<void> restoreEncryptedVmk();
  Future<void> restoreMetadataAndPhotos({required bool includePhotos});
}
