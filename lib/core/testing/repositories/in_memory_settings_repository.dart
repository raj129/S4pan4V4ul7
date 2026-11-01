import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

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

  String? _chatImageQuality;
  bool _autoLockOnBackground = true;
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

  bool _showLastSeen = true;

  @override
  Future<bool> isShowLastSeenEnabled() async => _showLastSeen;

  @override
  Future<void> setShowLastSeenEnabled(bool enabled) async {
    _showLastSeen = enabled;
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

  @override
  Future<String?> getMockLocationPrefs() async => _mockLocationPrefs;

  @override
  Future<void> setMockLocationPrefs(String json) async {
    _mockLocationPrefs = json;
  }
}
