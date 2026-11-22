import 'dart:convert';
import 'dart:typed_data';

import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import 'package:photo_vault/features/backup/domain/settings_backup_snapshot.dart';
import 'package:photo_vault/features/chat/application/services/saved_places_service.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_string_kv.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

class SettingsBackupResult {
  const SettingsBackupResult({
    required this.backupAt,
    required this.savedTo,
    this.skipped = const {},
  });

  final DateTime backupAt;
  final List<String> savedTo;
  final Map<String, Object> skipped;
}

class SettingsRestoreResult {
  const SettingsRestoreResult({
    required this.foundBackup,
    this.source,
    this.appliedCount = 0,
    this.skippedCount = 0,
  });

  final bool foundBackup;
  final String? source;
  final int appliedCount;
  final int skippedCount;
}

/// Backs up and restores portable app settings across [BackupByteStore]s
/// (device storage and Google Drive).
class SettingsBackupService {
  SettingsBackupService({
    required SettingsRepository settingsRepository,
    required List<BackupByteStore> stores,
    StorageStringKv? placesStore,
    this.networkAllowed,
  }) : _settingsRepository = settingsRepository,
       _stores = stores,
       _placesStore = placesStore;

  static const String blobName = 'settings_backup_v1.json';

  final SettingsRepository _settingsRepository;
  final List<BackupByteStore> _stores;
  final StorageStringKv? _placesStore;
  final Future<bool> Function()? networkAllowed;

  Future<SettingsBackupSnapshot> exportSnapshot() async {
    final themePaletteId = await _settingsRepository.getThemePaletteId();
    final themeMode = await _settingsRepository.getThemeMode();
    final autoLockOnBackground = await _settingsRepository
        .isAutoLockOnBackgroundEnabled();
    final autoLockTimeoutSeconds = await _settingsRepository
        .getAutoLockTimeoutSeconds();
    final secretEntryConfig = await _settingsRepository.getSecretEntryConfig();
    final showLastSeen = await _settingsRepository.isShowLastSeenEnabled();
    final screenshotProtectionEnabled = await _settingsRepository
        .isScreenshotProtectionEnabled();
    final hdrPhotoPreviewEnabled = await _settingsRepository
        .isHdrPhotoPreviewEnabled();
    final incomingChatAlertTitle = await _settingsRepository
        .getIncomingChatAlertTitle();
    final incomingChatAlertText = await _settingsRepository
        .getIncomingChatAlertText();
    final incomingChatAlertPreferences = await _settingsRepository
        .getIncomingChatAlertPreferences();
    final backgroundLocationAlertTitle = await _settingsRepository
        .getBackgroundLocationAlertTitle();
    final backgroundLocationAlertText = await _settingsRepository
        .getBackgroundLocationAlertText();
    final backupChatsEnabled = await _settingsRepository
        .isBackupChatsEnabled();
    final backupVaultPhotosEnabled = await _settingsRepository
        .isBackupVaultPhotosEnabled();
    final backupCloudEnabled = await _settingsRepository
        .isBackupCloudEnabled();
    final backupWifiOnly = await _settingsRepository.isBackupWifiOnly();
    final backupSettingsEnabled = await _settingsRepository
        .isBackupSettingsEnabled();
    final externalStorageMirrorEnabled = await _settingsRepository
        .isExternalStorageMirrorEnabled();
    final chatImageQuality = await _settingsRepository.getChatImageQuality();
    String? savedPlacesJson;
    String? placeTagsJson;
    if (_placesStore != null) {
      try {
        savedPlacesJson = await _placesStore.read(SavedPlacesService.storageKey);
        placeTagsJson = await _placesStore.read(
          SavedPlacesService.tagsStorageKey,
        );
      } catch (_) {}
    }

    return SettingsBackupSnapshot(
      createdAt: DateTime.now().toUtc(),
      themePaletteId: themePaletteId,
      themeMode: themeMode,
      autoLockOnBackground: autoLockOnBackground,
      autoLockTimeoutSeconds: autoLockTimeoutSeconds,
      secretEntryConfig: secretEntryConfig,
      showLastSeen: showLastSeen,
      screenshotProtectionEnabled: screenshotProtectionEnabled,
      hdrPhotoPreviewEnabled: hdrPhotoPreviewEnabled,
      incomingChatAlertTitle: incomingChatAlertTitle,
      incomingChatAlertText: incomingChatAlertText,
      incomingChatAlertPreferences: incomingChatAlertPreferences,
      backgroundLocationAlertTitle: backgroundLocationAlertTitle,
      backgroundLocationAlertText: backgroundLocationAlertText,
      backupChatsEnabled: backupChatsEnabled,
      backupVaultPhotosEnabled: backupVaultPhotosEnabled,
      backupCloudEnabled: backupCloudEnabled,
      backupWifiOnly: backupWifiOnly,
      backupSettingsEnabled: backupSettingsEnabled,
      externalStorageMirrorEnabled: externalStorageMirrorEnabled,
      chatImageQuality: chatImageQuality,
      savedPlacesJson: savedPlacesJson,
      placeTagsJson: placeTagsJson,
    );
  }

  Future<SettingsBackupResult> backup({bool interactive = false}) async {
    final snapshot = await exportSnapshot();
    final bytes = Uint8List.fromList(utf8.encode(snapshot.encode()));
    final cloudEnabled = await _settingsRepository.isBackupCloudEnabled();
    final savedTo = <String>[];
    final skipped = <String, Object>{};

    for (final store in _stores) {
      if (store.isCloud && !cloudEnabled) {
        skipped[store.label] = 'Cloud backup is off';
        continue;
      }
      if (store.requiresNetwork && networkAllowed != null) {
        final allowed = await networkAllowed!();
        if (!allowed) {
          skipped[store.label] = 'Waiting for Wi-Fi';
          continue;
        }
      }
      try {
        await store.writeBytes(blobName, bytes, interactive: interactive);
        savedTo.add(store.label);
      } catch (e) {
        skipped[store.label] = e;
      }
    }

    if (savedTo.isNotEmpty) {
      await _settingsRepository.setLastSettingsBackupAt(snapshot.createdAt);
    }

    return SettingsBackupResult(
      backupAt: snapshot.createdAt,
      savedTo: savedTo,
      skipped: skipped,
    );
  }

  Future<({bool hasLocal, bool hasCloud})> hasBackups({
    bool interactive = false,
    bool includeCloud = true,
  }) async {
    var hasLocal = false;
    var hasCloud = false;
    for (final store in _stores) {
      if (store.isCloud && !includeCloud) continue;
      try {
        final found = await store.list(blobName, interactive: interactive);
        if (found.contains(blobName)) {
          if (store.isCloud) {
            hasCloud = true;
          } else {
            hasLocal = true;
          }
        }
      } catch (_) {}
    }
    return (hasLocal: hasLocal, hasCloud: hasCloud);
  }

  Future<SettingsRestoreResult> restore({
    bool interactive = false,
    bool includeCloud = true,
    bool preferCloud = false,
  }) async {
    final orderedStores = List<BackupByteStore>.from(_stores)
      ..sort((a, b) {
        if (a.isCloud == b.isCloud) return 0;
        if (preferCloud) return a.isCloud ? -1 : 1;
        return a.isCloud ? 1 : -1;
      });

    for (final store in orderedStores) {
      if (store.isCloud && !includeCloud) continue;
      try {
        final bytes = await store.readBytes(blobName, interactive: interactive);
        if (bytes == null || bytes.isEmpty) continue;
        final snapshot = SettingsBackupSnapshot.decode(utf8.decode(bytes));
        final counts = await applySnapshot(snapshot);
        return SettingsRestoreResult(
          foundBackup: true,
          source: store.label,
          appliedCount: counts.applied,
          skippedCount: counts.skipped,
        );
      } catch (_) {
        // Try next store if this copy is missing or unreadable.
      }
    }

    return const SettingsRestoreResult(foundBackup: false);
  }

  /// Applies [snapshot] to [_settingsRepository] with per-setting isolation so
  /// any future/deprecated field mismatch never prevents other settings from
  /// restoring cleanly.
  Future<({int applied, int skipped})> applySnapshot(
    SettingsBackupSnapshot snapshot,
  ) async {
    var applied = 0;
    var skipped = 0;

    Future<void> tryApply(Future<void> Function() fn) async {
      try {
        await fn();
        applied++;
      } catch (_) {
        skipped++;
      }
    }

    if (snapshot.themePaletteId != null) {
      await tryApply(
        () => _settingsRepository.setThemePaletteId(snapshot.themePaletteId!),
      );
    }
    if (snapshot.themeMode != null) {
      await tryApply(
        () => _settingsRepository.setThemeMode(snapshot.themeMode!),
      );
    }
    if (snapshot.autoLockOnBackground != null) {
      await tryApply(
        () => _settingsRepository.setAutoLockOnBackgroundEnabled(
          snapshot.autoLockOnBackground!,
        ),
      );
    }
    if (snapshot.autoLockTimeoutSeconds != null) {
      await tryApply(
        () => _settingsRepository.setAutoLockTimeoutSeconds(
          snapshot.autoLockTimeoutSeconds!,
        ),
      );
    }
    if (snapshot.secretEntryConfig != null) {
      await tryApply(
        () => _settingsRepository.setSecretEntryConfig(
          snapshot.secretEntryConfig!,
        ),
      );
    }
    if (snapshot.showLastSeen != null) {
      await tryApply(
        () =>
            _settingsRepository.setShowLastSeenEnabled(snapshot.showLastSeen!),
      );
    }
    if (snapshot.screenshotProtectionEnabled != null) {
      await tryApply(
        () => _settingsRepository.setScreenshotProtectionEnabled(
          snapshot.screenshotProtectionEnabled!,
        ),
      );
    }
    if (snapshot.hdrPhotoPreviewEnabled != null) {
      await tryApply(
        () => _settingsRepository.setHdrPhotoPreviewEnabled(
          snapshot.hdrPhotoPreviewEnabled!,
        ),
      );
    }
    if (snapshot.incomingChatAlertTitle != null) {
      await tryApply(
        () => _settingsRepository.setIncomingChatAlertTitle(
          snapshot.incomingChatAlertTitle!,
        ),
      );
    }
    if (snapshot.incomingChatAlertText != null) {
      await tryApply(
        () => _settingsRepository.setIncomingChatAlertText(
          snapshot.incomingChatAlertText!,
        ),
      );
    }
    if (snapshot.incomingChatAlertPreferences != null) {
      await tryApply(
        () => _settingsRepository.setIncomingChatAlertPreferences(
          snapshot.incomingChatAlertPreferences!,
        ),
      );
    }
    if (snapshot.backgroundLocationAlertTitle != null) {
      await tryApply(
        () => _settingsRepository.setBackgroundLocationAlertTitle(
          snapshot.backgroundLocationAlertTitle!,
        ),
      );
    }
    if (snapshot.backgroundLocationAlertText != null) {
      await tryApply(
        () => _settingsRepository.setBackgroundLocationAlertText(
          snapshot.backgroundLocationAlertText!,
        ),
      );
    }
    if (snapshot.backupChatsEnabled != null) {
      await tryApply(
        () => _settingsRepository.setBackupChatsEnabled(
          snapshot.backupChatsEnabled!,
        ),
      );
    }
    if (snapshot.backupVaultPhotosEnabled != null) {
      await tryApply(
        () => _settingsRepository.setBackupVaultPhotosEnabled(
          snapshot.backupVaultPhotosEnabled!,
        ),
      );
    }
    if (snapshot.backupCloudEnabled != null) {
      await tryApply(
        () => _settingsRepository.setBackupCloudEnabled(
          snapshot.backupCloudEnabled!,
        ),
      );
    }
    if (snapshot.backupWifiOnly != null) {
      await tryApply(
        () => _settingsRepository.setBackupWifiOnly(snapshot.backupWifiOnly!),
      );
    }
    if (snapshot.backupSettingsEnabled != null) {
      await tryApply(
        () => _settingsRepository.setBackupSettingsEnabled(
          snapshot.backupSettingsEnabled!,
        ),
      );
    }
    if (snapshot.externalStorageMirrorEnabled != null) {
      await tryApply(
        () => _settingsRepository.setExternalStorageMirrorEnabled(
          snapshot.externalStorageMirrorEnabled!,
        ),
      );
    }
    if (snapshot.chatImageQuality != null) {
      await tryApply(
        () =>
            _settingsRepository.setChatImageQuality(snapshot.chatImageQuality!),
      );
    }
    if (_placesStore != null) {
      if (snapshot.savedPlacesJson != null &&
          snapshot.savedPlacesJson!.isNotEmpty) {
        await tryApply(
          () => _mergeJsonList(
            key: SavedPlacesService.storageKey,
            incomingRaw: snapshot.savedPlacesJson!,
            idField: 'id',
          ),
        );
      }
      if (snapshot.placeTagsJson != null &&
          snapshot.placeTagsJson!.isNotEmpty) {
        await tryApply(
          () => _mergeJsonList(
            key: SavedPlacesService.tagsStorageKey,
            incomingRaw: snapshot.placeTagsJson!,
            idField: 'name',
          ),
        );
      }
    }

    return (applied: applied, skipped: skipped);
  }

  Future<void> _mergeJsonList({
    required String key,
    required String incomingRaw,
    required String idField,
  }) async {
    final store = _placesStore;
    if (store == null) return;
    final incomingDecoded = jsonDecode(incomingRaw);
    if (incomingDecoded is! List) return;

    final existingRaw = await store.read(key);
    final existingList = <Map<String, dynamic>>[];
    final seenIds = <Object?>{};
    if (existingRaw != null && existingRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(existingRaw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final map = Map<String, dynamic>.from(item);
              existingList.add(map);
              seenIds.add(map[idField]);
            }
          }
        }
      } catch (_) {}
    }

    for (final item in incomingDecoded) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = map[idField];
      if (!seenIds.contains(id)) {
        existingList.add(map);
        seenIds.add(id);
      }
    }

    await store.write(key, jsonEncode(existingList));
  }

  Future<void> deleteBackup({
    bool device = true,
    bool cloud = true,
    bool interactive = false,
  }) async {
    for (final store in _stores) {
      if (store.isCloud && !cloud) continue;
      if (!store.isCloud && !device) continue;
      try {
        await store.delete(blobName, interactive: interactive);
      } catch (_) {}
    }
    if (device) {
      await _settingsRepository.setLastSettingsBackupAt(null);
    }
  }
}
