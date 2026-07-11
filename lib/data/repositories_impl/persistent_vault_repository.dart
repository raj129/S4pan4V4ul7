import '../../domain/entities/vault_settings.dart';
import '../../domain/entities/vault_status.dart';
import '../../domain/repositories/vault_repository.dart';
import 'storage_keys.dart';
import 'storage_mode_codec.dart';
import 'storage_string_kv.dart';

class PersistentVaultRepository implements VaultRepository {
  PersistentVaultRepository(this._kv);

  final StorageStringKv _kv;

  @override
  Future<VaultStatus> getStatus() async {
    final value = await _kv.read(StorageKeys.vaultStatus);
    return switch (value) {
      'creating' => VaultStatus.creating,
      'ready' => VaultStatus.ready,
      _ => VaultStatus.notCreated,
    };
  }

  @override
  Future<String?> getActiveVaultId() {
    return _kv.read(StorageKeys.vaultActiveId);
  }

  @override
  Future<void> markCreating({required String vaultId}) async {
    await _kv.write(StorageKeys.vaultCreatingId, vaultId);
    await _kv.write(StorageKeys.vaultStatus, 'creating');
  }

  @override
  Future<void> initializeVault({
    required String vaultId,
    required VaultSettings settings,
  }) async {
    await _kv.write(StorageKeys.vaultActiveId, vaultId);
    await _kv.write(StorageKeys.vaultStatus, 'ready');
    await _kv.delete(StorageKeys.vaultCreatingId);
    await _kv.write(StorageKeys.userMode, StorageModeCodec.serialize(settings.mode));
    await _kv.write(StorageKeys.biometricEnabled, settings.biometricEnabled.toString());
    await _kv.write(StorageKeys.appLockOnOpen, settings.appLockOnOpen.toString());
    await _kv.write(
      StorageKeys.autoLockOnBackground,
      settings.autoLockOnBackground.toString(),
    );
    await _kv.write(StorageKeys.photoSyncEnabled, settings.photoSyncEnabled.toString());
    await _kv.write(StorageKeys.vmkBackupEnabled, settings.vmkBackupEnabled.toString());
  }

  @override
  Future<void> deletePartialVault({required String vaultId}) async {
    final creatingId = await _kv.read(StorageKeys.vaultCreatingId);
    if (creatingId != vaultId) return;
    await _kv.delete(StorageKeys.vaultCreatingId);
    await _kv.write(StorageKeys.vaultStatus, 'notCreated');
  }
}
