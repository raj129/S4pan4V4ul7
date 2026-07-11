import '../entities/user_mode.dart';

abstract class SettingsRepository {
  Future<UserMode?> getUserMode();
  Future<void> saveUserMode(UserMode mode);
  Future<bool> isBiometricUnlockEnabled();
  Future<void> setBiometricUnlockEnabled(bool enabled);
  Future<bool> isPhotoSyncEnabled();
  Future<void> setPhotoSyncEnabled(bool enabled);
}
