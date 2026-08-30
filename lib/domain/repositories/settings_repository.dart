import '../entities/user_mode.dart';

abstract class SettingsRepository {
  Future<UserMode?> getUserMode();
  Future<void> saveUserMode(UserMode mode);
  Future<bool> isCalculatorOnboardingCompleted();
  Future<void> setCalculatorOnboardingCompleted(bool completed);
  Future<bool> isPhotoSyncEnabled();
  Future<void> setPhotoSyncEnabled(bool enabled);
  Future<bool> isExternalStorageMirrorEnabled();
  Future<void> setExternalStorageMirrorEnabled(bool enabled);
  Future<bool> isDriveEncryptedBackupEnabled();
  Future<void> setDriveEncryptedBackupEnabled(bool enabled);
}
