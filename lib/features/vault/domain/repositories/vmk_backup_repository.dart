/// Repository for backing up and restoring the wrapped VMK.
///
/// This handles off-device persistence of the recovery key.
abstract class VmkBackupRepository {
  /// Backs up the wrapped VMK and its associated metadata.
  ///
  /// [payload] contains the base64-encoded components (wrappedVmk, nonce, mac, salt).
  Future<void> backupVmk({
    required String vaultId,
    required Map<String, String> payload,
  });

  /// Attempts to restore the wrapped VMK for the given [vaultId].
  /// Returns null if no backup is found.
  Future<Map<String, String>?> restoreVmk(String vaultId);

  /// Checks if a backup exists for the given [vaultId].
  Future<bool> hasBackup(String vaultId);

  /// Lists all vault IDs that have a backup in this repository.
  Future<List<String>> listVaultIds();
}
