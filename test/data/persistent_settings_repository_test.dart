import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/vault/data/repositories/persistent_settings_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_keys.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_string_kv.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

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
    expect(
      await repository.getBackgroundLocationAlertText(),
      'Syncing in background',
    );

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

  test('rejects invalid timeout values', () async {
    final repository = PersistentSettingsRepository(_MemoryStringKv());

    await expectLater(
      repository.setAutoLockTimeoutSeconds(2),
      throwsArgumentError,
    );
  });
}
