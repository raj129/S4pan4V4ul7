import '../../domain/entities/user_mode.dart';
import '../../domain/repositories/settings_repository.dart';
import 'storage_keys.dart';
import 'storage_mode_codec.dart';
import 'storage_string_kv.dart';

class PersistentSettingsRepository implements SettingsRepository {
  PersistentSettingsRepository(this._kv);

  final StorageStringKv _kv;

  @override
  Future<UserMode?> getUserMode() async {
    final raw = await _kv.read(StorageKeys.userMode);
    return StorageModeCodec.parse(raw);
  }

  @override
  Future<void> saveUserMode(UserMode mode) {
    return _kv.write(StorageKeys.userMode, StorageModeCodec.serialize(mode));
  }

  @override
  Future<bool> isCalculatorOnboardingCompleted() async {
    final raw = await _kv.read(StorageKeys.calculatorOnboardingCompleted);
    return raw == 'true';
  }

  @override
  Future<void> setCalculatorOnboardingCompleted(bool completed) {
    return _kv.write(
      StorageKeys.calculatorOnboardingCompleted,
      completed.toString(),
    );
  }

  @override
  Future<bool> isPhotoSyncEnabled() async {
    final raw = await _kv.read(StorageKeys.photoSyncEnabled);
    return raw == 'true';
  }

  @override
  Future<void> setPhotoSyncEnabled(bool enabled) {
    return _kv.write(StorageKeys.photoSyncEnabled, enabled.toString());
  }

  @override
  Future<bool> isExternalStorageMirrorEnabled() async {
    final raw = await _kv.read(StorageKeys.externalStorageMirrorEnabled);
    return raw == null ? true : raw == 'true';
  }

  @override
  Future<void> setExternalStorageMirrorEnabled(bool enabled) {
    return _kv.write(
      StorageKeys.externalStorageMirrorEnabled,
      enabled.toString(),
    );
  }

  @override
  Future<bool> isDriveEncryptedBackupEnabled() async {
    final raw = await _kv.read(StorageKeys.driveEncryptedBackupEnabled);
    return raw == 'true';
  }

  @override
  Future<void> setDriveEncryptedBackupEnabled(bool enabled) {
    return _kv.write(StorageKeys.driveEncryptedBackupEnabled, enabled.toString());
  }
}
