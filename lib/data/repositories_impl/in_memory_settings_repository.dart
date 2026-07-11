import '../../domain/entities/user_mode.dart';
import '../../domain/repositories/settings_repository.dart';

class InMemorySettingsRepository implements SettingsRepository {
  UserMode? _selectedMode;
  bool _biometricUnlockEnabled = false;
  bool _photoSyncEnabled = false;

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
}
