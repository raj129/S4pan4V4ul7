import 'dart:convert';

import '../../domain/entities/user_mode.dart';
import '../../domain/entities/incoming_chat_alert_preferences.dart';
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

  Future<bool> _readDefaultTrue(String key) async {
    final raw = await _kv.read(key);
    return raw == null ? true : raw == 'true';
  }

  @override
  Future<bool> isBackupChatsEnabled() =>
      _readDefaultTrue(StorageKeys.backupChatsEnabled);

  @override
  Future<void> setBackupChatsEnabled(bool enabled) =>
      _kv.write(StorageKeys.backupChatsEnabled, enabled.toString());

  @override
  Future<bool> isBackupVaultPhotosEnabled() =>
      _readDefaultTrue(StorageKeys.backupVaultPhotosEnabled);

  @override
  Future<void> setBackupVaultPhotosEnabled(bool enabled) =>
      _kv.write(StorageKeys.backupVaultPhotosEnabled, enabled.toString());

  @override
  Future<bool> isBackupCloudEnabled() async {
    final raw = await _kv.read(StorageKeys.backupCloudEnabled);
    return raw == 'true';
  }

  @override
  Future<void> setBackupCloudEnabled(bool enabled) =>
      _kv.write(StorageKeys.backupCloudEnabled, enabled.toString());

  @override
  Future<bool> isBackupWifiOnly() =>
      _readDefaultTrue(StorageKeys.backupWifiOnly);

  @override
  Future<void> setBackupWifiOnly(bool enabled) =>
      _kv.write(StorageKeys.backupWifiOnly, enabled.toString());

  @override
  Future<DateTime?> getLastVaultPhotoBackupAt() async {
    final ms = int.tryParse(
      await _kv.read(StorageKeys.lastVaultPhotoBackupAt) ?? '',
    );
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  @override
  Future<void> setLastVaultPhotoBackupAt(DateTime? at) async {
    if (at == null) {
      await _kv.delete(StorageKeys.lastVaultPhotoBackupAt);
      return;
    }
    await _kv.write(
      StorageKeys.lastVaultPhotoBackupAt,
      at.millisecondsSinceEpoch.toString(),
    );
  }

  @override
  Future<String?> getLastVaultPhotoBackupVaultId() =>
      _kv.read(StorageKeys.lastVaultPhotoBackupVaultId);

  @override
  Future<void> setLastVaultPhotoBackupVaultId(String? vaultId) async {
    if (vaultId == null) {
      await _kv.delete(StorageKeys.lastVaultPhotoBackupVaultId);
      return;
    }
    await _kv.write(StorageKeys.lastVaultPhotoBackupVaultId, vaultId);
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
  Future<String> getIncomingChatAlertTitle() async {
    final raw = await _kv.read(StorageKeys.incomingChatAlertTitle);
    return raw == null
        ? SettingsRepository.defaultIncomingChatAlertTitle
        : raw.trim();
  }

  @override
  Future<void> setIncomingChatAlertTitle(String title) =>
      _kv.write(StorageKeys.incomingChatAlertTitle, title.trim());

  @override
  Future<void> setIncomingChatAlertText(String text) async {
    final value = text.trim();
    await _kv.write(StorageKeys.incomingChatAlertText, value);
  }

  @override
  Future<IncomingChatAlertPreferences> getIncomingChatAlertPreferences() async {
    final raw = await _kv.read(StorageKeys.incomingChatAlertPreferences);
    if (raw == null) return const IncomingChatAlertPreferences();
    try {
      return IncomingChatAlertPreferences.fromJson(jsonDecode(raw));
    } on FormatException {
      return const IncomingChatAlertPreferences();
    }
  }

  @override
  Future<void> setIncomingChatAlertPreferences(
    IncomingChatAlertPreferences preferences,
  ) => _kv.write(
    StorageKeys.incomingChatAlertPreferences,
    jsonEncode(preferences.toJson()),
  );

  @override
  Future<String> getBackgroundLocationAlertTitle() async {
    final raw = await _kv.read(StorageKeys.backgroundLocationAlertTitle);
    return raw == null
        ? SettingsRepository.defaultBackgroundLocationAlertTitle
        : raw.trim();
  }

  @override
  Future<void> setBackgroundLocationAlertTitle(String title) =>
      _kv.write(StorageKeys.backgroundLocationAlertTitle, title.trim());

  @override
  Future<String> getBackgroundLocationAlertText() async {
    final raw = await _kv.read(StorageKeys.backgroundLocationAlertText);
    return raw == null
        ? SettingsRepository.defaultBackgroundLocationAlertText
        : raw.trim();
  }

  @override
  Future<void> setBackgroundLocationAlertText(String text) =>
      _kv.write(StorageKeys.backgroundLocationAlertText, text.trim());

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
  Future<bool> isHdrPhotoPreviewEnabled() async {
    final raw = await _kv.read(StorageKeys.hdrPhotoPreviewEnabled);
    return raw == null ? true : raw == 'true';
  }

  @override
  Future<void> setHdrPhotoPreviewEnabled(bool enabled) =>
      _kv.write(StorageKeys.hdrPhotoPreviewEnabled, enabled.toString());

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
