import '../../domain/entities/user_mode.dart';
import '../../domain/repositories/settings_repository.dart';

class InMemorySettingsRepository implements SettingsRepository {
  UserMode? _selectedMode;

  @override
  Future<UserMode?> getUserMode() async => _selectedMode;

  @override
  Future<void> saveUserMode(UserMode mode) async {
    _selectedMode = mode;
  }
}
