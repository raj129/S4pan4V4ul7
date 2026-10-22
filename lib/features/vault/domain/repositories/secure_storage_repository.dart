/// Handles encrypted persistence of vault key material.
///
/// Security rules:
/// - This is the ONLY repository that may write wrapped VMK blobs.
/// - Raw VMK bytes must NEVER be passed to or returned from this layer.
/// - All storage is backed by platform-secure storage (Android Keystore / DPAPI).
abstract class SecureStorageRepository {
  /// Persists the wrapped VMK blob and its KDF salt for [vaultId].
  ///
  /// [wrappedVmkBase64] — AES-GCM ciphertext of the VMK, base64-encoded.
  /// [nonceBase64]      — 96-bit AES-GCM nonce, base64-encoded.
  /// [macBase64]        — 128-bit GCM authentication tag, base64-encoded.
  /// [saltBase64]       — KDF (PBKDF2) salt, base64-encoded.
  /// [encVersion]       — encryption scheme version for future migration.
  Future<void> storeWrappedVmk({
    required String vaultId,
    required String wrappedVmkBase64,
    required String nonceBase64,
    required String macBase64,
    required String saltBase64,
    required int encVersion,
  });

  /// Retrieves the wrapped VMK record for [vaultId].
  /// Returns null if no record exists (vault not set up yet).
  Future<Map<String, String>?> loadWrappedVmk(String vaultId);

  /// Removes all VMK-related blobs for [vaultId].
  /// Called on vault deletion or creation cleanup.
  Future<void> deleteVmkBlobs(String vaultId);
}
