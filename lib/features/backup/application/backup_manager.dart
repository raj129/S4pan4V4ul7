import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:photo_vault/core/app/external_activity_guard.dart';
import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/features/backup/application/backup_error_formatter.dart';
import 'package:photo_vault/features/backup/application/backup_progress.dart';
import 'package:photo_vault/features/backup/application/vault_photo_backup_service.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

enum BackupOperation { connectingDrive, backingUp, restoring, deleting }

enum BackupNoticeTone { info, success, warning, error }

@immutable
class BackupNotice {
  const BackupNotice({required this.message, required this.tone});

  final String message;
  final BackupNoticeTone tone;
}

/// App-scoped backup & restore orchestrator.
///
/// Lives above route state so ongoing manual or automatic backups keep running
/// across navigation and auto-lock, while Settings, Backup & Restore, and the
/// Gallery header observe live status silently without breaking the stealth
/// Calculator cover.
class BackupManager extends ChangeNotifier {
  BackupManager({
    required SettingsRepository settingsRepository,
    required ChatBackupService? Function() chatBackup,
    required VaultPhotoBackupService Function() vaultPhotoBackup,
    AuthRepository? authRepository,
    Future<void> Function()? onSettingsChanged,
    Future<void> Function({required bool wifiOnly})? scheduleCatchUp,
    BackupProgressReporter? progressReporter,
  }) : _settingsRepository = settingsRepository,
       _chatBackup = chatBackup,
       _vaultPhotoBackup = vaultPhotoBackup,
       _authRepository = authRepository,
       onSettingsChanged = onSettingsChanged,
       _scheduleCatchUp = scheduleCatchUp,
       _progressReporter = progressReporter ?? backupProgress {
    _progressReporter.state.addListener(_onProgressChanged);
  }

  final SettingsRepository _settingsRepository;
  final ChatBackupService? Function() _chatBackup;
  final VaultPhotoBackupService Function() _vaultPhotoBackup;
  final AuthRepository? _authRepository;
  Future<void> Function()? onSettingsChanged;
  final Future<void> Function({required bool wifiOnly})? _scheduleCatchUp;
  final BackupProgressReporter _progressReporter;

  bool _loaded = false;
  bool _disposed = false;
  BackupOperation? _activeOperation;

  bool _chatsEnabled = true;
  bool _photosEnabled = true;
  bool _cloudEnabled = true;
  bool _wifiOnly = true;
  bool _externalMirrorEnabled = true;
  DateTime? _lastChatBackupAt;
  DateTime? _lastPhotoBackupAt;
  bool _chatCloudPending = false;
  bool _photoCloudPending = false;
  UserMode? _userMode;
  BackupNotice? _lastNotice;

  bool get isLoaded => _loaded;
  bool get isBusy => _activeOperation != null;
  BackupOperation? get activeOperation => _activeOperation;
  BackupProgress? get progress => _progressReporter.state.value;

  bool get chatsEnabled => _chatsEnabled;
  bool get photosEnabled => _photosEnabled;
  bool get cloudEnabled => _cloudEnabled;
  bool get wifiOnly => _wifiOnly;
  bool get externalMirrorEnabled => _externalMirrorEnabled;
  DateTime? get lastChatBackupAt => _lastChatBackupAt;
  DateTime? get lastPhotoBackupAt => _lastPhotoBackupAt;
  bool get chatCloudPending => _chatCloudPending;
  bool get photoCloudPending => _photoCloudPending;
  UserMode? get userMode => _userMode;
  BackupNotice? get lastNotice => _lastNotice;

  bool get isAnyBackupEnabled => _chatsEnabled || _photosEnabled;

  bool get hasPendingCloudUpload =>
      _cloudEnabled &&
      ((_chatsEnabled && _chatCloudPending) ||
          (_photosEnabled && _photoCloudPending));

  /// True when vault photo backup is active, has completed at least once, and
  /// has no pending cloud upload or active backup job.
  bool get isGalleryBackedUp =>
      _photosEnabled &&
      !isBusy &&
      !(_cloudEnabled && _photoCloudPending) &&
      _lastPhotoBackupAt != null;

  DateTime? get latestBackupAt {
    final a = _chatsEnabled ? _lastChatBackupAt : null;
    final b = _photosEnabled ? _lastPhotoBackupAt : null;
    if (a == null) return b;
    if (b == null) return a;
    return a.isAfter(b) ? a : b;
  }

  /// Human-friendly single-line status for the Settings screen entry.
  String settingsSummary({String Function(DateTime)? formatTime}) {
    if (isBusy) {
      return progress?.label ?? _operationLabel(_activeOperation!);
    }
    if (!_loaded) {
      return 'Manage backups, restore chats/photos, and recover a vault.';
    }
    if (!isAnyBackupEnabled) {
      return 'Automatic backups are turned off.';
    }
    if (hasPendingCloudUpload) {
      return _wifiOnly
          ? 'Saved on this device · Waiting for Wi-Fi to upload to Drive'
          : 'Saved on this device · Google Drive upload pending';
    }
    final where = _cloudEnabled
        ? 'This device & Google Drive'
        : 'This device only';
    final latest = latestBackupAt;
    if (latest == null) {
      return '$where · Not backed up yet';
    }
    final fmt = formatTime ?? formatTimestamp;
    return '$where · Last: ${fmt(latest)}';
  }

  static String _operationLabel(BackupOperation op) => switch (op) {
    BackupOperation.connectingDrive => 'Connecting Google Drive…',
    BackupOperation.backingUp => 'Backing up…',
    BackupOperation.restoring => 'Restoring from backup…',
    BackupOperation.deleting => 'Deleting backup…',
  };

  static String formatTimestamp(DateTime at) {
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  static String _countLabel(int count, String singular, String plural) =>
      '$count ${count == 1 ? singular : plural}';

  void _onProgressChanged() {
    _notifySafely();
  }

  void _notifySafely() {
    if (!_disposed) notifyListeners();
  }

  void clearNotice() {
    if (_lastNotice == null) return;
    _lastNotice = null;
    _notifySafely();
  }

  Future<void> load() async {
    await _settingsRepository.migrateLegacyPhotoSyncSetting();
    final chatsOn = await _settingsRepository.isBackupChatsEnabled();
    final photosOn = await _settingsRepository.isBackupVaultPhotosEnabled();
    final cloudOn = await _settingsRepository.isBackupCloudEnabled();
    final mirrorOn = await _settingsRepository.isExternalStorageMirrorEnabled();
    final lastPhotos = await _settingsRepository.getLastVaultPhotoBackupAt();
    final photoPending = await _settingsRepository
        .isVaultPhotoBackupCloudPending();
    final mode = await _settingsRepository.getUserMode();
    DateTime? lastChats;
    var chatPending = false;
    try {
      final chat = _chatBackup();
      await chat?.migrateLegacyWifiSetting();
      lastChats = await chat?.lastBackupAt();
      chatPending = await chat?.isCloudPending() ?? false;
    } catch (_) {
      // Chat unavailable (local mode or offline): leave chat timestamps unset.
    }
    final wifiOnly = await _settingsRepository.isBackupWifiOnly();
    _chatsEnabled = chatsOn;
    _photosEnabled = photosOn;
    _cloudEnabled = cloudOn;
    _wifiOnly = wifiOnly;
    _externalMirrorEnabled = mirrorOn;
    _lastChatBackupAt = lastChats;
    _lastPhotoBackupAt = lastPhotos;
    _chatCloudPending = chatPending;
    _photoCloudPending = photoPending;
    _userMode = mode;
    _loaded = true;
    _notifySafely();
  }

  /// Runs overdue or cloud-pending backups silently on app launch / resume.
  Future<void> backupIfDue() async {
    try {
      await _settingsRepository.migrateLegacyPhotoSyncSetting();
      try {
        await _vaultPhotoBackup().backupIfDue();
      } catch (_) {}
      try {
        final chat = _chatBackup();
        await chat?.backupIfDue();
      } catch (_) {}
      await load();
      await scheduleCatchUpIfNeeded();
    } catch (_) {}
  }

  /// Enqueues an OS network-constrained catch-up job when work is still pending
  /// or when the app moves to the background mid-backup.
  Future<void> scheduleCatchUpIfNeeded({bool forceIfBusy = false}) async {
    final schedule = _scheduleCatchUp;
    if (schedule == null) return;
    if (hasPendingCloudUpload ||
        (forceIfBusy && _activeOperation == BackupOperation.backingUp)) {
      try {
        await schedule(wifiOnly: _wifiOnly);
      } catch (_) {}
    }
  }

  Future<void> setChatsEnabled(bool value) async {
    _chatsEnabled = value;
    _notifySafely();
    await _settingsRepository.setBackupChatsEnabled(value);
  }

  Future<void> setPhotosEnabled(bool value) async {
    _photosEnabled = value;
    _notifySafely();
    await _settingsRepository.setBackupVaultPhotosEnabled(value);
    await _settingsRepository.setPhotoSyncEnabled(value);
    await onSettingsChanged?.call();
  }

  /// Enables or disables Google Drive backups.
  ///
  /// When turning Google Drive ON and an [AuthRepository] is wired, signs in if
  /// needed and warms up Drive OAuth immediately so background 2 AM backups
  /// already hold authorization. Reverts to false if authorization fails.
  Future<BackupNotice?> setCloudEnabled(bool value) async {
    if (!value) {
      _cloudEnabled = false;
      _notifySafely();
      await _settingsRepository.setBackupCloudEnabled(false);
      await _settingsRepository.setDriveEncryptedBackupEnabled(false);
      await onSettingsChanged?.call();
      return null;
    }

    final auth = _authRepository;
    if (auth != null) {
      if (isBusy) return null;
      _activeOperation = BackupOperation.connectingDrive;
      _lastNotice = null;
      _notifySafely();
      try {
        await ExternalActivityGuard.run(() async {
          if (!await auth.isSignedIn()) {
            await auth.signInWithGoogle();
            await _settingsRepository.saveUserMode(UserMode.googleEnabled);
            _userMode = UserMode.googleEnabled;
          }
          await auth.warmUpDriveAuthorization(interactive: true);
        });
      } catch (e) {
        _cloudEnabled = false;
        _activeOperation = null;
        final notice = BackupNotice(
          message:
              'Could not connect Google Drive: ${BackupErrorFormatter.brief(e)}',
          tone: BackupNoticeTone.error,
        );
        _lastNotice = notice;
        _notifySafely();
        return notice;
      } finally {
        if (_activeOperation == BackupOperation.connectingDrive) {
          _activeOperation = null;
        }
      }
    }

    _cloudEnabled = true;
    await _settingsRepository.setBackupCloudEnabled(true);
    await _settingsRepository.setDriveEncryptedBackupEnabled(true);
    await onSettingsChanged?.call();
    _notifySafely();
    await scheduleCatchUpIfNeeded();
    return null;
  }

  Future<void> setWifiOnly(bool value) async {
    _wifiOnly = value;
    _notifySafely();
    await _settingsRepository.setBackupWifiOnly(value);
    await scheduleCatchUpIfNeeded();
  }

  Future<void> setExternalMirrorEnabled(bool value) async {
    _externalMirrorEnabled = value;
    _notifySafely();
    await _settingsRepository.setExternalStorageMirrorEnabled(value);
    await onSettingsChanged?.call();
  }

  Future<BackupNotice> backUpNow() async {
    if (isBusy) {
      return const BackupNotice(
        message: 'Another backup action is already running.',
        tone: BackupNoticeTone.info,
      );
    }
    if (!_loaded) await load();
    if (!_chatsEnabled && !_photosEnabled) {
      const notice = BackupNotice(
        message: 'Turn on chats or vault photos to back up.',
        tone: BackupNoticeTone.warning,
      );
      _lastNotice = notice;
      _notifySafely();
      return notice;
    }

    _activeOperation = BackupOperation.backingUp;
    _lastNotice = null;
    _notifySafely();

    final parts = <String>[];
    final notes = <String>[];
    final failures = <String>[];
    try {
      if (_chatsEnabled) {
        try {
          final chat = _chatBackup();
          if (chat == null) {
            failures.add('chats unavailable');
          } else {
            final result = await chat.backupNow(interactive: true);
            _lastChatBackupAt = result.backupAt;
            if (result.messageCount == 0) {
              notes.add('No chat messages were available to back up');
            } else if (result.savedTo.isEmpty) {
              failures.add('chats: no backup destination saved the data');
            } else {
              parts.add(
                '${_countLabel(result.messageCount, 'chat message', 'chat messages')} '
                'to ${result.savedTo.join(', ')}',
              );
            }
            notes.addAll(
              result.skipped.entries
                  .where((e) => e.value != 'Cloud backup is off')
                  .map((e) => '${e.key}: ${BackupErrorFormatter.brief(e.value)}'),
            );
          }
        } catch (e) {
          failures.add('chats: ${BackupErrorFormatter.brief(e)}');
        }
      }
      if (_photosEnabled) {
        try {
          final result = await _vaultPhotoBackup().backup(interactive: true);
          _lastPhotoBackupAt = await _settingsRepository
              .getLastVaultPhotoBackupAt();
          if (result.photoCount == 0) {
            notes.add(
              result.missingCount == 0
                  ? 'No vault photos were available to back up'
                  : 'No vault photos were backed up',
            );
          } else if (result.savedTo.isEmpty) {
            failures.add(
              'vault photos: no backup destination saved the manifest',
            );
          } else {
            parts.add(
              '${_countLabel(result.photoCount, 'vault photo', 'vault photos')} '
              'to ${result.savedTo.join(', ')}',
            );
          }
          if (result.missingCount > 0) {
            notes.add(
              '${_countLabel(result.missingCount, 'photo', 'photos')} '
              'were missing on this device',
            );
          }
          if (!result.completed) {
            notes.add(
              'Vault photo backup stopped before all photos were checked',
            );
          }
          notes.addAll(
            result.skipped.entries
                .where((e) => e.value != 'Cloud backup is off')
                .map((e) => '${e.key}: ${BackupErrorFormatter.brief(e.value)}'),
          );
        } catch (e) {
          failures.add('vault photos: ${BackupErrorFormatter.brief(e)}');
        }
      }

      await _refreshPendingFlags();
      await scheduleCatchUpIfNeeded();

      final summary = parts.isEmpty
          ? 'Nothing was backed up.'
          : 'Backed up ${parts.join(' and ')}.';
      final failed = failures.isEmpty ? '' : ' Failed: ${failures.join('; ')}.';
      final extra = notes.isEmpty ? '' : ' ${notes.join('. ')}.';
      final tone = failures.isNotEmpty
          ? (parts.isNotEmpty ? BackupNoticeTone.warning : BackupNoticeTone.error)
          : (notes.isNotEmpty ? BackupNoticeTone.info : BackupNoticeTone.success);
      final notice = BackupNotice(
        message: _clampSummary('$summary$failed$extra'),
        tone: tone,
      );
      _lastNotice = notice;
      return notice;
    } finally {
      _activeOperation = null;
      _notifySafely();
    }
  }

  Future<BackupNotice> restoreFromBackup() async {
    if (isBusy) {
      return const BackupNotice(
        message: 'Another backup action is already running.',
        tone: BackupNoticeTone.info,
      );
    }
    if (!_loaded) await load();

    _activeOperation = BackupOperation.restoring;
    _lastNotice = null;
    _notifySafely();

    final parts = <String>[];
    final notes = <String>[];
    final failures = <String>[];
    var foundBackup = false;
    try {
      try {
        final chat = _chatBackup();
        if (chat == null) {
          if (_chatsEnabled) {
            failures.add('Chats are unavailable on this device');
          }
        } else {
          final snapshot = await chat.findLatestBackup(interactive: true);
          if (snapshot != null) {
            foundBackup = true;
            final restored = await chat.restore(snapshot);
            if (restored > 0) {
              parts.add(
                '${_countLabel(restored, 'chat message', 'chat messages')} '
                'from ${snapshot.source}',
              );
            } else {
              notes.add('The chat backup had no messages to restore');
            }
          }
        }
      } catch (e) {
        failures.add('chats: ${BackupErrorFormatter.brief(e)}');
      }
      try {
        final photos = await _vaultPhotoBackup().restore(interactive: true);
        foundBackup |= photos.foundBackup;
        if (photos.restored > 0) {
          parts.add(
            _countLabel(photos.restored, 'vault photo', 'vault photos'),
          );
        }
        if (photos.alreadyPresent > 0) {
          notes.add(
            '${_countLabel(photos.alreadyPresent, 'vault photo', 'vault photos')} '
            'were already on this device',
          );
        }
        if (photos.unavailable > 0) {
          notes.add(
            '${_countLabel(photos.unavailable, 'vault photo', 'vault photos')} '
            'could not be recovered',
          );
        }
        notes.addAll(photos.failures.map(BackupErrorFormatter.brief));
      } catch (e) {
        failures.add('vault photos: ${BackupErrorFormatter.brief(e)}');
      }

      final summary = parts.isNotEmpty
          ? 'Restored ${parts.join(' and ')}.'
          : foundBackup
          ? 'Backup found, but no new items were restored.'
          : failures.isNotEmpty
          ? 'Could not restore from the available backups.'
          : 'No backup found in the enabled locations.';
      final failed = failures.isEmpty ? '' : ' Failed: ${failures.join('; ')}.';
      final extra = notes.isEmpty ? '' : ' ${notes.join('. ')}.';
      final tone = failures.isNotEmpty
          ? (parts.isNotEmpty ? BackupNoticeTone.warning : BackupNoticeTone.error)
          : (parts.isNotEmpty ? BackupNoticeTone.success : BackupNoticeTone.info);
      final notice = BackupNotice(
        message: _clampSummary('$summary$failed$extra'),
        tone: tone,
      );
      _lastNotice = notice;
      return notice;
    } finally {
      _activeOperation = null;
      _notifySafely();
    }
  }

  Future<BackupNotice> deleteBackup({
    required bool device,
    required bool cloud,
  }) async {
    if (isBusy) {
      return const BackupNotice(
        message: 'Another backup action is already running.',
        tone: BackupNoticeTone.info,
      );
    }
    _activeOperation = BackupOperation.deleting;
    _lastNotice = null;
    _notifySafely();
    try {
      await _chatBackup()?.deleteBackup(device: device, cloud: cloud);
      await _vaultPhotoBackup().deleteBackup(device: device, cloud: cloud);
      if (device) {
        await _settingsRepository.setLastVaultPhotoBackupAt(null);
        await _settingsRepository.setLastVaultPhotoBackupVaultId(null);
      }
      if (cloud) {
        await _settingsRepository.setVaultPhotoBackupCloudPending(false);
      }
      await load();
      const notice = BackupNotice(
        message: 'Backup deleted.',
        tone: BackupNoticeTone.success,
      );
      _lastNotice = notice;
      return notice;
    } catch (e) {
      final notice = BackupNotice(
        message: 'Delete failed: ${BackupErrorFormatter.brief(e)}',
        tone: BackupNoticeTone.error,
      );
      _lastNotice = notice;
      return notice;
    } finally {
      _activeOperation = null;
      _notifySafely();
    }
  }

  Future<void> _refreshPendingFlags() async {
    try {
      _photoCloudPending = await _settingsRepository
          .isVaultPhotoBackupCloudPending();
    } catch (_) {}
    try {
      _chatCloudPending = await _chatBackup()?.isCloudPending() ?? false;
    } catch (_) {}
  }

  static String _clampSummary(String message) =>
      message.length > 280 ? '${message.substring(0, 280)}…' : message;

  @override
  void dispose() {
    _disposed = true;
    _progressReporter.state.removeListener(_onProgressChanged);
    super.dispose();
  }
}
