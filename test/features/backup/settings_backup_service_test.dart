import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/features/backup/application/settings_backup_service.dart';
import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import 'package:photo_vault/features/backup/domain/settings_backup_snapshot.dart';
import 'package:photo_vault/features/calculator/domain/models/secret_entry_config.dart';

class _InMemoryByteStore extends BackupByteStore {
  _InMemoryByteStore({required this.label, required this.isCloud});

  @override
  final String label;

  @override
  final bool isCloud;

  @override
  bool get requiresNetwork => isCloud;

  final Map<String, Uint8List> blobs = {};

  @override
  Future<void> writeBytes(
    String name,
    Uint8List bytes, {
    bool interactive = false,
  }) async {
    blobs[name] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> readBytes(String name, {bool interactive = false}) async =>
      blobs[name];

  @override
  Future<List<String>> list(String prefix, {bool interactive = false}) async =>
      blobs.keys.where((k) => k.startsWith(prefix)).toList();

  @override
  Future<void> delete(String name, {bool interactive = false}) async {
    blobs.remove(name);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('SettingsBackupSnapshot handles schema evolution and legacy keys', () {
    const raw = '''
    {
      "schemaVersion": 99,
      "createdAt": 1700000000000,
      "settings": {
        "themePaletteId": "unknown_future_palette",
        "themeMode": "dark",
        "autoLockTimeoutMinutes": 5,
        "photoSyncEnabled": true,
        "driveEncryptedBackupEnabled": true,
        "futureToggle": true
      }
    }
    ''';

    final snapshot = SettingsBackupSnapshot.decode(raw);
    expect(snapshot.schemaVersion, 99);
    expect(snapshot.themePaletteId, 'indigo');
    expect(snapshot.themeMode, 'dark');
    expect(snapshot.autoLockTimeoutSeconds, 60);
    expect(snapshot.backupVaultPhotosEnabled, isTrue);
    expect(snapshot.backupCloudEnabled, isTrue);
    expect(snapshot.unknownFields['futureToggle'], isTrue);

    final roundTrip = SettingsBackupSnapshot.decode(snapshot.encode());
    expect(roundTrip.unknownFields['futureToggle'], isTrue);
  });

  test('SettingsBackupService backs up and restores settings', () async {
    final sourceRepo = InMemorySettingsRepository();
    await sourceRepo.setThemePaletteId('emerald');
    await sourceRepo.setThemeMode('dark');
    await sourceRepo.setAutoLockTimeoutSeconds(30);
    await sourceRepo.setShowLastSeenEnabled(false);
    await sourceRepo.setBackupCloudEnabled(true);
    await sourceRepo.setSecretEntryConfig(
      SecretEntryConfig.defaultsFor(
        SecretEntryMethod.sequentialHold,
        oneHandedEnabled: true,
      ),
    );

    final localStore = _InMemoryByteStore(label: 'This device', isCloud: false);
    final cloudStore = _InMemoryByteStore(label: 'Google Drive', isCloud: true);

    final backupService = SettingsBackupService(
      settingsRepository: sourceRepo,
      stores: [localStore, cloudStore],
    );

    final result = await backupService.backup(interactive: true);
    expect(result.savedTo, ['This device', 'Google Drive']);

    final targetRepo = InMemorySettingsRepository();
    final restoreService = SettingsBackupService(
      settingsRepository: targetRepo,
      stores: [localStore, cloudStore],
    );

    final probed = await restoreService.hasBackups(includeCloud: true);
    expect(probed.hasLocal, isTrue);
    expect(probed.hasCloud, isTrue);

    final restored = await restoreService.restore(
      includeCloud: true,
      preferCloud: true,
    );
    expect(restored.foundBackup, isTrue);
    expect(restored.source, 'Google Drive');
    expect(await targetRepo.getThemePaletteId(), 'emerald');
    expect(await targetRepo.getThemeMode(), 'dark');
    expect(await targetRepo.getAutoLockTimeoutSeconds(), 30);
    expect(await targetRepo.isShowLastSeenEnabled(), isFalse);
    expect((await targetRepo.getSecretEntryConfig()).oneHandedEnabled, isTrue);
  });
}
