import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/vault/data/repositories/persistent_settings_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_keys.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_string_kv.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/features/vault/domain/entities/incoming_chat_alert_preferences.dart';

class _MemoryStringKv implements StorageStringKv {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('screenshot protection defaults on and persists user choice', () async {
    final kv = _MemoryStringKv();
    final repository = PersistentSettingsRepository(kv);

    expect(await repository.isScreenshotProtectionEnabled(), isTrue);

    await repository.setScreenshotProtectionEnabled(false);

    expect(await repository.isScreenshotProtectionEnabled(), isFalse);
    expect(kv.values[StorageKeys.screenshotProtectionEnabled], 'false');
  });

  test('HDR photo preview defaults on and persists user choice', () async {
    final kv = _MemoryStringKv();
    final repository = PersistentSettingsRepository(kv);

    expect(await repository.isHdrPhotoPreviewEnabled(), isTrue);

    await repository.setHdrPhotoPreviewEnabled(false);

    expect(await repository.isHdrPhotoPreviewEnabled(), isFalse);
    expect(kv.values[StorageKeys.hdrPhotoPreviewEnabled], 'false');
  });

  test('provides defaults and persists timeout and alert text', () async {
    final kv = _MemoryStringKv();
    final repository = PersistentSettingsRepository(kv);

    expect(await repository.getAutoLockTimeoutSeconds(), 10);
    expect(await repository.getIncomingChatAlertTitle(), isEmpty);
    expect(await repository.getIncomingChatAlertText(), isEmpty);
    expect(await repository.getBackgroundLocationAlertTitle(), isEmpty);
    expect(await repository.getBackgroundLocationAlertText(), '');

    await repository.setAutoLockTimeoutSeconds(30);
    await repository.setIncomingChatAlertTitle('  Private  ');
    await repository.setIncomingChatAlertText('  New message  ');
    await repository.setBackgroundLocationAlertTitle('  Location  ');
    await repository.setBackgroundLocationAlertText('  Sharing location  ');

    expect(await repository.getAutoLockTimeoutSeconds(), 30);
    expect(await repository.getIncomingChatAlertTitle(), 'Private');
    expect(await repository.getIncomingChatAlertText(), 'New message');
    expect(await repository.getBackgroundLocationAlertTitle(), 'Location');
    expect(
      await repository.getBackgroundLocationAlertText(),
      'Sharing location',
    );

    await repository.setIncomingChatAlertTitle('');
    await repository.setIncomingChatAlertText('');
    await repository.setBackgroundLocationAlertTitle('');
    await repository.setBackgroundLocationAlertText('');
    expect(await repository.getIncomingChatAlertTitle(), isEmpty);
    expect(await repository.getIncomingChatAlertText(), isEmpty);
    expect(await repository.getBackgroundLocationAlertTitle(), isEmpty);
    expect(await repository.getBackgroundLocationAlertText(), isEmpty);
  });

  test('migrates a prior minute-based timeout to one minute', () async {
    final kv = _MemoryStringKv()
      ..values[StorageKeys.legacyAutoLockTimeoutMinutes] = '5';
    final repository = PersistentSettingsRepository(kv);

    expect(await repository.getAutoLockTimeoutSeconds(), 60);
    expect(kv.values[StorageKeys.autoLockTimeoutSeconds], '60');
  });

  test('falls back to the default for an unsupported timeout value', () async {
    final kv = _MemoryStringKv()
      ..values[StorageKeys.autoLockTimeoutSeconds] = '2';
    final repository = PersistentSettingsRepository(kv);

    expect(
      await repository.getAutoLockTimeoutSeconds(),
      SettingsRepository.defaultAutoLockTimeoutSeconds,
    );
  });

  test('persists independent incoming-chat alert preferences', () async {
    final kv = _MemoryStringKv();
    final repository = PersistentSettingsRepository(kv);
    const preferences = IncomingChatAlertPreferences(
      source: NotificationAlertSource.custom,
      ringSoundEnabled: false,
      vibrationEnabled: true,
      vibrationPattern: IncomingChatVibrationPattern.shortPulses,
      notificationSoundUri: 'content://settings/system/notification',
      flashlightEnabled: true,
    );

    expect(
      await repository.getIncomingChatAlertPreferences(),
      const IncomingChatAlertPreferences(),
    );
    await repository.setIncomingChatAlertPreferences(preferences);

    expect(await repository.getIncomingChatAlertPreferences(), preferences);
    expect(
      kv.values[StorageKeys.incomingChatAlertPreferences],
      contains('"source":"custom"'),
    );
  });

  test('migrates a stored ringtone URI to the notification sound field', () {
    final preferences = IncomingChatAlertPreferences.fromJson({
      'source': 'custom',
      'ringtoneUri': 'content://settings/system/notification',
    });

    expect(
      preferences.notificationSoundUri,
      'content://settings/system/notification',
    );
    expect(preferences.vibrationPattern, IncomingChatVibrationPattern.standard);
  });

  test('rejects invalid timeout values', () async {
    final repository = PersistentSettingsRepository(_MemoryStringKv());

    await expectLater(
      repository.setAutoLockTimeoutSeconds(2),
      throwsArgumentError,
    );
  });

  test('migrates legacy photoSyncEnabled into backupVaultPhotosEnabled once without disabling fresh vaults', () async {
    final kv = _MemoryStringKv()
      ..values[StorageKeys.photoSyncEnabled] = 'true';
    final repository = PersistentSettingsRepository(kv);

    await repository.migrateLegacyPhotoSyncSetting();

    expect(kv.values[StorageKeys.backupVaultPhotosEnabled], 'true');
    expect(kv.values[StorageKeys.legacyPhotoSyncMigrated], 'true');

    // Explicit user changes afterwards are not overwritten by re-running migration.
    await repository.setBackupVaultPhotosEnabled(false);
    await repository.migrateLegacyPhotoSyncSetting();
    expect(await repository.isBackupVaultPhotosEnabled(), isFalse);
  });

  test('persists vaultPhotoBackupCloudPending flag', () async {
    final repository = PersistentSettingsRepository(_MemoryStringKv());

    expect(await repository.isVaultPhotoBackupCloudPending(), isFalse);
    await repository.setVaultPhotoBackupCloudPending(true);
    expect(await repository.isVaultPhotoBackupCloudPending(), isTrue);
  });
}
