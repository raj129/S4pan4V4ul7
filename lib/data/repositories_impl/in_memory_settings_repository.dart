import '../../domain/entities/user_mode.dart';
import '../../domain/repositories/settings_repository.dart';

class InMemorySettingsRepository implements SettingsRepository {
  UserMode? _selectedMode;
  bool _biometricUnlockEnabled = false;
  bool _photoSyncEnabled = false;
  bool _externalStorageMirrorEnabled = true;
  bool _driveEncryptedBackupEnabled = false;

  @override
  Future<UserMode?> getUserMode() async => _selectedMode;

  @override
  Future<void> saveUserMode(UserMode mode) async {
    _selectedMode = mode;
  }

  @override
  Future<bool> isBiometricUnlockEnabled() async => _biometricUnlockEnabled;

  @override
  Future<void> setBiometricUnlockEnabled(bool enabled) async {
    _biometricUnlockEnabled = enabled;
  }

  @override
  Future<bool> isPhotoSyncEnabled() async => _photoSyncEnabled;

  @override
  Future<void> setPhotoSyncEnabled(bool enabled) async {
    _photoSyncEnabled = enabled;
  }

  @override
  Future<bool> isExternalStorageMirrorEnabled() async =>
      _externalStorageMirrorEnabled;

  @override
  Future<void> setExternalStorageMirrorEnabled(bool enabled) async {
    _externalStorageMirrorEnabled = enabled;
  }

  @override
  Future<bool> isDriveEncryptedBackupEnabled() async =>
      _driveEncryptedBackupEnabled;

  @override
  Future<void> setDriveEncryptedBackupEnabled(bool enabled) async {
    _driveEncryptedBackupEnabled = enabled;
  }
}
