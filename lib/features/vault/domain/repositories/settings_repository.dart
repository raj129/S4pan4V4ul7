import '../entities/user_mode.dart';

abstract class SettingsRepository {
  static const defaultAutoLockTimeoutSeconds = 10;
  static const autoLockTimeoutOptionsSeconds = [5, 10, 30, 60];
  static const defaultIncomingChatAlertTitle = '';
  static const defaultIncomingChatAlertText = '';
  static const defaultBackgroundLocationAlertTitle = '';
  static const defaultBackgroundLocationAlertText = 'Syncing in background';

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

  Future<int> getAutoLockTimeoutSeconds() async =>
      defaultAutoLockTimeoutSeconds;

  Future<void> setAutoLockTimeoutSeconds(int seconds) async {}

  /// Title shown in incoming-chat notification alerts.
  Future<String> getIncomingChatAlertTitle() async =>
      defaultIncomingChatAlertTitle;

  Future<void> setIncomingChatAlertTitle(String title) async {}

  /// Body text shown in incoming-chat notification alerts.
  Future<String> getIncomingChatAlertText() async =>
      defaultIncomingChatAlertText;

  Future<void> setIncomingChatAlertText(String text) async {}

  /// Title and body shown while live location is shared in the background.
  Future<String> getBackgroundLocationAlertTitle() async =>
      defaultBackgroundLocationAlertTitle;

  Future<void> setBackgroundLocationAlertTitle(String title) async {}

  Future<String> getBackgroundLocationAlertText() async =>
      defaultBackgroundLocationAlertText;

  Future<void> setBackgroundLocationAlertText(String text) async {}

  /// Whether contacts may see when this user was last online. Reciprocal:
  /// when off, the user cannot see anyone else's last seen either.
  Future<bool> isShowLastSeenEnabled() async => true;

  Future<void> setShowLastSeenEnabled(bool enabled) async {}

  /// Whether Android screenshots and screen recordings should be blocked.
  Future<bool> isScreenshotProtectionEnabled() async => true;

  Future<void> setScreenshotProtectionEnabled(bool enabled) async {}

  /// Whether supported devices should render HDR photos with HDR color mode.
  Future<bool> isHdrPhotoPreviewEnabled() async => true;

  Future<void> setHdrPhotoPreviewEnabled(bool enabled) async {}

  /// Persisted theme palette id (e.g. 'indigo', 'ocean', 'violet', 'emerald', 'rose', 'amber').
  Future<String?> getThemePaletteId() async => null;

  Future<void> setThemePaletteId(String paletteId) async {}

  /// Persisted theme mode ('system', 'light', 'dark').
  Future<String?> getThemeMode() async => null;

  Future<void> setThemeMode(String mode) async {}

  /// Saved mock-location setup as an opaque JSON string. Whether mock is
  /// active is never persisted.
  Future<String?> getMockLocationPrefs() async => null;

  Future<void> setMockLocationPrefs(String json) async {}
}
