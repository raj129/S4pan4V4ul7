import '../../domain/entities/vault_settings.dart';
import '../../domain/entities/vault_status.dart';
import '../../domain/repositories/vault_repository.dart';

/// In-memory vault repository used during development and unit tests.
///
/// Replace with a Drift/SQLite-backed implementation for production.
class InMemoryVaultRepository implements VaultRepository {
  VaultStatus _status = VaultStatus.notCreated;
  String? _creatingId;
  String? _activeVaultId;

  @override
  Future<VaultStatus> getStatus() async => _status;

  @override
  Future<String?> getActiveVaultId() async => _activeVaultId;

  @override
  Future<void> markCreating({required String vaultId}) async {
    _creatingId = vaultId;
    _status = VaultStatus.creating;
  }

  @override
  Future<void> initializeVault({
    required String vaultId,
    required VaultSettings settings,
  }) async {
    _creatingId = null;
    _activeVaultId = vaultId;
    _status = VaultStatus.ready;
  }

  @override
  Future<void> deletePartialVault({required String vaultId}) async {
    if (_creatingId == vaultId) {
      _creatingId = null;
      _status = VaultStatus.notCreated;
    }
  }
}
