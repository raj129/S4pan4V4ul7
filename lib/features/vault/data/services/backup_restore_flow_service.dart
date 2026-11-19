import '../../application/services/restore_flow_service.dart';
import '../../application/usecases/restore_vault_usecase.dart';
import '../../domain/repositories/vault_repository.dart';

class BackupRestoreFlowService implements RestoreFlowService {
  BackupRestoreFlowService({
    required RestoreVaultUseCase restoreVaultUseCase,
    required VaultRepository vaultRepository,
    required Future<RestorePhotosSummary> Function() restorePhotos,
    Future<void> Function({
      required String vaultId,
      required String originalPin,
      required String newPin,
    })?
    onVaultRestored,
  }) : _restoreVaultUseCase = restoreVaultUseCase,
       _vaultRepository = vaultRepository,
       _restorePhotos = restorePhotos,
       _onVaultRestored = onVaultRestored;

  final RestoreVaultUseCase _restoreVaultUseCase;
  final VaultRepository _vaultRepository;
  final Future<RestorePhotosSummary> Function() _restorePhotos;
  final Future<void> Function({
    required String vaultId,
    required String originalPin,
    required String newPin,
  })?
  _onVaultRestored;

  @override
  Future<List<String>> listVaultIds() =>
      _restoreVaultUseCase.listVaultIds(interactive: true);

  @override
  Future<String?> activeVaultId() => _vaultRepository.getActiveVaultId();

  @override
  Future<void> restoreVault({
    required String vaultId,
    required String originalPin,
    required String newPin,
  }) async {
    await _restoreVaultUseCase.execute(
      vaultId: vaultId,
      originalPin: originalPin,
      newPin: newPin,
    );
    await _onVaultRestored?.call(
      vaultId: vaultId,
      originalPin: originalPin,
      newPin: newPin,
    );
  }

  @override
  Future<RestorePhotosSummary> restorePhotos({
    required bool includePhotos,
  }) async {
    if (!includePhotos) {
      return const RestorePhotosSummary(
        foundBackup: false,
        restored: 0,
        alreadyPresent: 0,
        unavailable: 0,
      );
    }
    return _restorePhotos();
  }
}
