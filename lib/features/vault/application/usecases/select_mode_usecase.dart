import '../../domain/entities/user_mode.dart';
import '../../domain/repositories/settings_repository.dart';

class SelectModeUseCase {
  SelectModeUseCase(this._settingsRepository);

  final SettingsRepository _settingsRepository;

  Future<UserMode?> currentMode() {
    return _settingsRepository.getUserMode();
  }

  Future<void> execute(UserMode mode) {
    return _settingsRepository.saveUserMode(mode);
  }
}
