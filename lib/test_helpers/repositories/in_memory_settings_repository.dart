import '../../domain/entities/user_mode.dart';
import '../../domain/repositories/settings_repository.dart';

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

  @override
  Future<String?> getChatImageQuality() async => _chatImageQuality;

  @override
  Future<void> setChatImageQuality(String quality) async {
    _chatImageQuality = quality;
  }

  String? _chatVideoQuality;

  @override
  Future<String?> getChatVideoQuality() async => _chatVideoQuality;

  @override
  Future<void> setChatVideoQuality(String quality) async {
    _chatVideoQuality = quality;
  }
}
