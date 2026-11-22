import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/entities/incoming_chat_alert_preferences.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/features/calculator/domain/models/secret_entry_config.dart';

class InMemorySettingsRepository implements SettingsRepository {
  UserMode? _selectedMode;
  bool _calculatorOnboardingCompleted = false;
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
  Future<bool> isCalculatorOnboardingCompleted() async =>
      _calculatorOnboardingCompleted;

  @override
  Future<void> setCalculatorOnboardingCompleted(bool completed) async {
    _calculatorOnboardingCompleted = completed;
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

  bool _backupChatsEnabled = true;
  bool _backupVaultPhotosEnabled = true;
  bool _backupSettingsEnabled = true;
  bool _backupCloudEnabled = false;
  bool _backupWifiOnly = true;
  DateTime? _lastVaultPhotoBackupAt;
  DateTime? _lastSettingsBackupAt;
  String? _lastVaultPhotoBackupVaultId;
  bool _vaultPhotoBackupCloudPending = false;

  @override
  Future<bool> isBackupChatsEnabled() async => _backupChatsEnabled;

  @override
  Future<void> setBackupChatsEnabled(bool enabled) async {
    _backupChatsEnabled = enabled;
  }

  @override
  Future<bool> isBackupVaultPhotosEnabled() async => _backupVaultPhotosEnabled;

  @override
  Future<void> setBackupVaultPhotosEnabled(bool enabled) async {
    _backupVaultPhotosEnabled = enabled;
  }

  @override
  Future<bool> isBackupSettingsEnabled() async => _backupSettingsEnabled;

  @override
  Future<void> setBackupSettingsEnabled(bool enabled) async {
    _backupSettingsEnabled = enabled;
  }

  @override
  Future<DateTime?> getLastSettingsBackupAt() async => _lastSettingsBackupAt;

  @override
  Future<void> setLastSettingsBackupAt(DateTime? at) async {
    _lastSettingsBackupAt = at;
  }

  @override
  Future<bool> isBackupCloudEnabled() async => _backupCloudEnabled;

  @override
  Future<void> setBackupCloudEnabled(bool enabled) async {
    _backupCloudEnabled = enabled;
  }

  @override
  Future<bool> isBackupWifiOnly() async => _backupWifiOnly;

  @override
  Future<void> setBackupWifiOnly(bool enabled) async {
    _backupWifiOnly = enabled;
  }

  @override
  Future<DateTime?> getLastVaultPhotoBackupAt() async =>
      _lastVaultPhotoBackupAt;

  @override
  Future<void> setLastVaultPhotoBackupAt(DateTime? at) async {
    _lastVaultPhotoBackupAt = at;
  }

  @override
  Future<String?> getLastVaultPhotoBackupVaultId() async =>
      _lastVaultPhotoBackupVaultId;

  @override
  Future<void> setLastVaultPhotoBackupVaultId(String? vaultId) async {
    _lastVaultPhotoBackupVaultId = vaultId;
  }

  @override
  Future<bool> isVaultPhotoBackupCloudPending() async =>
      _vaultPhotoBackupCloudPending;

  @override
  Future<void> setVaultPhotoBackupCloudPending(bool pending) async {
    _vaultPhotoBackupCloudPending = pending;
  }

  @override
  Future<void> migrateLegacyPhotoSyncSetting() async {}

  String? _chatImageQuality;
  bool _autoLockOnBackground = true;
  int _autoLockTimeoutSeconds =
      SettingsRepository.defaultAutoLockTimeoutSeconds;
  String _incomingChatAlertTitle =
      SettingsRepository.defaultIncomingChatAlertTitle;
  String _incomingChatAlertText =
      SettingsRepository.defaultIncomingChatAlertText;
  IncomingChatAlertPreferences _incomingChatAlertPreferences =
      const IncomingChatAlertPreferences();
  String _backgroundLocationAlertTitle =
      SettingsRepository.defaultBackgroundLocationAlertTitle;
  String _backgroundLocationAlertText =
      SettingsRepository.defaultBackgroundLocationAlertText;
  String? _themePaletteId;
  String? _themeMode;

  @override
  Future<String?> getChatImageQuality() async => _chatImageQuality;

  @override
  Future<void> setChatImageQuality(String quality) async {
    _chatImageQuality = quality;
  }

  @override
  Future<bool> isAutoLockOnBackgroundEnabled() async => _autoLockOnBackground;

  @override
  Future<void> setAutoLockOnBackgroundEnabled(bool enabled) async {
    _autoLockOnBackground = enabled;
  }

  @override
  Future<int> getAutoLockTimeoutSeconds() async => _autoLockTimeoutSeconds;

  @override
  Future<void> setAutoLockTimeoutSeconds(int seconds) async {
    if (!SettingsRepository.autoLockTimeoutOptionsSeconds.contains(seconds)) {
      throw ArgumentError.value(
        seconds,
        'seconds',
        'Unsupported auto-lock timeout.',
      );
    }
    _autoLockTimeoutSeconds = seconds;
  }

  @override
  Future<String> getIncomingChatAlertTitle() async => _incomingChatAlertTitle;

  @override
  Future<void> setIncomingChatAlertTitle(String title) async {
    _incomingChatAlertTitle = title.trim();
  }

  @override
  Future<String> getIncomingChatAlertText() async => _incomingChatAlertText;

  @override
  Future<void> setIncomingChatAlertText(String text) async {
    _incomingChatAlertText = text.trim();
  }

  @override
  Future<IncomingChatAlertPreferences>
  getIncomingChatAlertPreferences() async => _incomingChatAlertPreferences;

  @override
  Future<void> setIncomingChatAlertPreferences(
    IncomingChatAlertPreferences preferences,
  ) async {
    _incomingChatAlertPreferences = preferences;
  }

  @override
  Future<String> getBackgroundLocationAlertTitle() async =>
      _backgroundLocationAlertTitle;

  @override
  Future<void> setBackgroundLocationAlertTitle(String title) async {
    _backgroundLocationAlertTitle = title.trim();
  }

  @override
  Future<String> getBackgroundLocationAlertText() async =>
      _backgroundLocationAlertText;

  @override
  Future<void> setBackgroundLocationAlertText(String text) async {
    _backgroundLocationAlertText = text.trim();
  }

  bool _showLastSeen = true;
  bool _screenshotProtectionEnabled = true;
  bool _hdrPhotoPreviewEnabled = true;

  @override
  Future<bool> isShowLastSeenEnabled() async => _showLastSeen;

  @override
  Future<void> setShowLastSeenEnabled(bool enabled) async {
    _showLastSeen = enabled;
  }

  @override
  Future<bool> isScreenshotProtectionEnabled() async =>
      _screenshotProtectionEnabled;

  @override
  Future<void> setScreenshotProtectionEnabled(bool enabled) async {
    _screenshotProtectionEnabled = enabled;
  }

  @override
  Future<bool> isHdrPhotoPreviewEnabled() async => _hdrPhotoPreviewEnabled;

  @override
  Future<void> setHdrPhotoPreviewEnabled(bool enabled) async {
    _hdrPhotoPreviewEnabled = enabled;
  }

  @override
  Future<String?> getThemePaletteId() async => _themePaletteId;

  @override
  Future<void> setThemePaletteId(String paletteId) async {
    _themePaletteId = paletteId;
  }

  @override
  Future<String?> getThemeMode() async => _themeMode;

  @override
  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
  }

  String? _mockLocationPrefs;
  SecretEntryConfig _secretEntryConfig = const SecretEntryConfig();

  @override
  Future<String?> getMockLocationPrefs() async => _mockLocationPrefs;

  @override
  Future<void> setMockLocationPrefs(String json) async {
    _mockLocationPrefs = json;
  }

  @override
  Future<SecretEntryConfig> getSecretEntryConfig() async => _secretEntryConfig;

  @override
  Future<void> setSecretEntryConfig(SecretEntryConfig config) async {
    _secretEntryConfig = config;
  }
}
