import '../entities/vault_settings.dart';
import '../entities/vault_status.dart';

/// Manages vault lifecycle: creation, status check, and cleanup on failure.
///
/// Security rule: this repository NEVER receives or stores raw VMK bytes.
/// Wrapped VMK blobs are managed by [SecureStorageRepository].
abstract class VaultRepository {
  /// Returns the current vault status.
  Future<VaultStatus> getStatus();

  /// Persists vault settings after successful vault creation.
  Future<void> initializeVault({
    required String vaultId,
    required VaultSettings settings,
  });

  /// Marks vault creation as in-progress (to detect interrupted creation on restart).
  Future<void> markCreating({required String vaultId});

  /// Removes any partial vault record created during a failed [initializeVault].
  Future<void> deletePartialVault({required String vaultId});
}
