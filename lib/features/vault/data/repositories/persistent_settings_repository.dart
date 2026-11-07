import '../../domain/entities/user_mode.dart';
import '../../domain/repositories/settings_repository.dart';
import 'storage_keys.dart';
import 'storage_mode_codec.dart';
import 'storage_string_kv.dart';

class PersistentSettingsRepository implements SettingsRepository {
  PersistentSettingsRepository(this._kv);

  final StorageStringKv _kv;

  @override
  Future<UserMode?> getUserMode() async {
    final raw = await _kv.read(StorageKeys.userMode);
    return StorageModeCodec.parse(raw);
  }

  @override
  Future<void> saveUserMode(UserMode mode) {
    return _kv.write(StorageKeys.userMode, StorageModeCodec.serialize(mode));
  }

  @override
  Future<bool> isCalculatorOnboardingCompleted() async {
    final raw = await _kv.read(StorageKeys.calculatorOnboardingCompleted);
    return raw == 'true';
  }

  @override
  Future<void> setCalculatorOnboardingCompleted(bool completed) {
    return _kv.write(
      StorageKeys.calculatorOnboardingCompleted,
      completed.toString(),
    );
  }

  @override
  Future<bool> isPhotoSyncEnabled() async {
    final raw = await _kv.read(StorageKeys.photoSyncEnabled);
    return raw == 'true';
  }

  @override
  Future<void> setPhotoSyncEnabled(bool enabled) {
    return _kv.write(StorageKeys.photoSyncEnabled, enabled.toString());
  }

  @override
  Future<bool> isExternalStorageMirrorEnabled() async {
    final raw = await _kv.read(StorageKeys.externalStorageMirrorEnabled);
    return raw == null ? true : raw == 'true';
  }

  @override
  Future<void> setExternalStorageMirrorEnabled(bool enabled) {
    return _kv.write(
      StorageKeys.externalStorageMirrorEnabled,
      enabled.toString(),
    );
  }

  @override
  Future<bool> isDriveEncryptedBackupEnabled() async {
    final raw = await _kv.read(StorageKeys.driveEncryptedBackupEnabled);
    return raw == 'true';
  }

  @override
  Future<void> setDriveEncryptedBackupEnabled(bool enabled) {
    return _kv.write(
      StorageKeys.driveEncryptedBackupEnabled,
      enabled.toString(),
    );
  }

  @override
  Future<String?> getChatImageQuality() =>
      _kv.read(StorageKeys.chatImageQuality);

  @override
  Future<void> setChatImageQuality(String quality) =>
      _kv.write(StorageKeys.chatImageQuality, quality);

  @override
  Future<bool> isAutoLockOnBackgroundEnabled() async {
    final raw = await _kv.read(StorageKeys.autoLockOnBackground);
    return raw == null ? true : raw == 'true';
  }

  @override
  Future<void> setAutoLockOnBackgroundEnabled(bool enabled) =>
      _kv.write(StorageKeys.autoLockOnBackground, enabled.toString());

  @override
  Future<int> getAutoLockTimeoutSeconds() async {
    final rawSeconds = await _kv.read(StorageKeys.autoLockTimeoutSeconds);
    if (rawSeconds != null) {
      final seconds = int.tryParse(rawSeconds);
      return SettingsRepository.autoLockTimeoutOptionsSeconds.contains(seconds)
          ? seconds!
          : SettingsRepository.defaultAutoLockTimeoutSeconds;
    }

    final rawMinutes = await _kv.read(StorageKeys.legacyAutoLockTimeoutMinutes);
    final legacyMinutes = int.tryParse(rawMinutes ?? '');
    if (![1, 5, 10, 15].contains(legacyMinutes)) {
      return SettingsRepository.defaultAutoLockTimeoutSeconds;
    }

    const migratedSeconds = 60;
    await _kv.write(
      StorageKeys.autoLockTimeoutSeconds,
      migratedSeconds.toString(),
    );
    return migratedSeconds;
  }

  @override
  Future<void> setAutoLockTimeoutSeconds(int seconds) async {
    if (!SettingsRepository.autoLockTimeoutOptionsSeconds.contains(seconds)) {
      throw ArgumentError.value(
        seconds,
        'seconds',
        'Unsupported auto-lock timeout.',
      );
    }
    await _kv.write(StorageKeys.autoLockTimeoutSeconds, seconds.toString());
  }

  @override
  Future<String> getIncomingChatAlertText() async {
    final raw = await _kv.read(StorageKeys.incomingChatAlertText);
    return raw == null
        ? SettingsRepository.defaultIncomingChatAlertText
        : raw.trim();
  }

  @override
  Future<void> setIncomingChatAlertText(String text) async {
    final value = text.trim();
    await _kv.write(StorageKeys.incomingChatAlertText, value);
  }

  @override
  Future<bool> isShowLastSeenEnabled() async {
    final raw = await _kv.read(StorageKeys.showLastSeen);
    return raw == null ? true : raw == 'true';
  }

  @override
  Future<void> setShowLastSeenEnabled(bool enabled) =>
      _kv.write(StorageKeys.showLastSeen, enabled.toString());

  @override
  Future<bool> isScreenshotProtectionEnabled() async {
    final raw = await _kv.read(StorageKeys.screenshotProtectionEnabled);
    return raw == null ? true : raw == 'true';
  }

  @override
  Future<void> setScreenshotProtectionEnabled(bool enabled) =>
      _kv.write(StorageKeys.screenshotProtectionEnabled, enabled.toString());

  @override
  Future<String?> getThemePaletteId() => _kv.read(StorageKeys.themePalette);

  @override
  Future<void> setThemePaletteId(String paletteId) =>
      _kv.write(StorageKeys.themePalette, paletteId);

  @override
  Future<String?> getThemeMode() => _kv.read(StorageKeys.themeMode);

  @override
  Future<void> setThemeMode(String mode) =>
      _kv.write(StorageKeys.themeMode, mode);

  @override
  Future<String?> getMockLocationPrefs() =>
      _kv.read(StorageKeys.mockLocationPrefs);

  @override
  Future<void> setMockLocationPrefs(String json) =>
      _kv.write(StorageKeys.mockLocationPrefs, json);
}
