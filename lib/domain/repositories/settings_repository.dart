import '../entities/user_mode.dart';

abstract class SettingsRepository {
  Future<UserMode?> getUserMode();
  Future<void> saveUserMode(UserMode mode);
}
