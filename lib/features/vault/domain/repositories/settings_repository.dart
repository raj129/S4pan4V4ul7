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

  /// Last attachment quality the user picked, preselected next time.
  Future<String?> getChatImageQuality();
  Future<void> setChatImageQuality(String quality);

  /// Whether the vault should automatically lock when backgrounded.
  Future<bool> isAutoLockOnBackgroundEnabled() async => true;
  Future<void> setAutoLockOnBackgroundEnabled(bool enabled) async {}

  /// Persisted theme palette id (e.g. 'indigo', 'ocean', 'violet', 'emerald', 'rose', 'amber').
  Future<String?> getThemePaletteId() async => null;
  Future<void> setThemePaletteId(String paletteId) async {}

  /// Persisted theme mode ('system', 'light', 'dark').
  Future<String?> getThemeMode() async => null;
  Future<void> setThemeMode(String mode) async {}
}
