import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';
import 'package:photo_vault/features/backup/application/backup_progress.dart';
import 'package:photo_vault/features/backup/application/vault_photo_backup_service.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/features/vault/presentation/widgets/pin_reauth_dialog.dart';

/// Every backup setting in one place: what to back up, where, status and
/// progress, manual backup, restore, and delete.
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    required this.settingsRepository,
    required this.chatBackup,
    required this.vaultPhotoBackup,
    required this.unlockVaultUseCase,
    required this.pinValidator,
    super.key,
  });

  final SettingsRepository settingsRepository;

  /// Resolved lazily: chat touches Firebase and is unavailable in local mode.
  final ChatBackupService? Function() chatBackup;
  final VaultPhotoBackupService Function() vaultPhotoBackup;
  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

enum _DeleteTarget { device, cloud, both }

class _BackupScreenState extends State<BackupScreen> {
  bool _chatsOn = true;
  bool _photosOn = true;
  bool _cloudOn = true;
  bool _wifiOnly = true;
  bool _externalMirrorOn = true;
  DateTime? _lastChatBackup;
  DateTime? _lastPhotoBackup;
  UserMode? _mode;
  bool _busy = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final settings = widget.settingsRepository;
    final chatsOn = await settings.isBackupChatsEnabled();
    final photosOn = await settings.isBackupVaultPhotosEnabled();
    final cloudOn = await settings.isBackupCloudEnabled();
    final mirrorOn = await settings.isExternalStorageMirrorEnabled();
    final lastPhotos = await settings.getLastVaultPhotoBackupAt();
    final mode = await settings.getUserMode();
    DateTime? lastChats;
    try {
      final chat = widget.chatBackup();
      await chat?.migrateLegacyWifiSetting();
      lastChats = await chat?.lastBackupAt();
    } catch (_) {
      // Chat unavailable (local mode or offline): show "never".
    }
    final wifiOnly = await settings.isBackupWifiOnly();
    if (!mounted) return;
    setState(() {
      _chatsOn = chatsOn;
      _photosOn = photosOn;
      _cloudOn = cloudOn;
      _wifiOnly = wifiOnly;
      _externalMirrorOn = mirrorOn;
      _lastChatBackup = lastChats;
      _lastPhotoBackup = lastPhotos;
      _mode = mode;
      _loaded = true;
    });
  }

  Future<void> _recoverGoogleVault() async {
    if (_busy) return;
    final allowed = await requirePinReauth(
      context: context,
      unlockVaultUseCase: widget.unlockVaultUseCase,
      pinValidator: widget.pinValidator,
      actionLabel: 'recover a Google vault',
    );
    if (!allowed || !mounted) return;
    await context.push('/restore');
  }

  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // SnackBars belong to the app-wide messenger and outlive this route; a
    // leftover one would be laid out under the next screen when going back.
    _messenger?.clearSnackBars();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    _messenger?.showSnackBar(
      SnackBar(
        content: Text(message, maxLines: 3, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  /// Short, single-line version of an error for a SnackBar. Raw errors from
  /// Drive or Firestore can be pages of text.
  static String _briefError(Object error) {
    final text = error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.contains('Google Drive API has not been used') ||
        text.contains('drive.googleapis.com/overview')) {
      return 'Google Drive API is disabled for this project. Enable '
          'drive.googleapis.com in Google Cloud, then retry.';
    }
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }

  static String _countLabel(int count, String singular, String plural) =>
      '$count ${count == 1 ? singular : plural}';

  static String _formatTime(DateTime at) {
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _setChats(bool value) async {
    setState(() => _chatsOn = value);
    await widget.settingsRepository.setBackupChatsEnabled(value);
  }

  Future<void> _setPhotos(bool value) async {
    setState(() => _photosOn = value);
    await widget.settingsRepository.setBackupVaultPhotosEnabled(value);
  }

  Future<void> _setCloud(bool value) async {
    setState(() => _cloudOn = value);
    await widget.settingsRepository.setBackupCloudEnabled(value);
  }

  Future<void> _setWifiOnly(bool value) async {
    setState(() => _wifiOnly = value);
    await widget.settingsRepository.setBackupWifiOnly(value);
  }

  Future<void> _setExternalMirror(bool value) async {
    setState(() => _externalMirrorOn = value);
    await widget.settingsRepository.setExternalStorageMirrorEnabled(value);
  }

  Future<void> _backUpNow() async {
    if (_busy) return;
    if (!_chatsOn && !_photosOn) {
      _showMessage('Turn on chats or vault photos to back up.');
      return;
    }
    setState(() => _busy = true);
    final parts = <String>[];
    final notes = <String>[];
    final failures = <String>[];
    try {
      // Each part runs on its own, so a failure in one never skips the other.
      if (_chatsOn) {
        try {
          final chat = widget.chatBackup();
          if (chat == null) {
            failures.add('chats unavailable');
          } else {
            final result = await chat.backupNow(interactive: true);
            _lastChatBackup = result.backupAt;
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
              result.skipped.entries.map(
                (e) => '${e.key}: ${_briefError(e.value)}',
              ),
            );
          }
        } catch (e) {
          failures.add('chats: ${_briefError(e)}');
        }
      }
      if (_photosOn) {
        try {
          // The service records the time itself when the run completes.
          final result = await widget.vaultPhotoBackup().backup(
            interactive: true,
          );
          _lastPhotoBackup = await widget.settingsRepository
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
            result.skipped.entries.map(
              (e) => '${e.key}: ${_briefError(e.value)}',
            ),
          );
        } catch (e) {
          failures.add('vault photos: ${_briefError(e)}');
        }
      }
      final summary = parts.isEmpty
          ? 'Nothing was backed up.'
          : 'Backed up ${parts.join(' and ')}.';
      final failed = failures.isEmpty ? '' : ' Failed: ${failures.join('; ')}.';
      final extra = notes.isEmpty ? '' : ' ${notes.join('. ')}.';
      _showMessage('$summary$failed$extra');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    if (_busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.restore_rounded),
        title: const Text('Restore from backup?'),
        content: const Text(
          'This phone’s copy is used first, then Google Drive. Items already '
          'on this phone are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final parts = <String>[];
    final notes = <String>[];
    final failures = <String>[];
    var foundBackup = false;
    try {
      try {
        final chat = widget.chatBackup();
        if (chat == null) {
          failures.add('Chats are unavailable on this device');
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
        failures.add('chats: ${_briefError(e)}');
      }
      try {
        final photos = await widget.vaultPhotoBackup().restore(
          interactive: true,
        );
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
        notes.addAll(photos.failures.map(_briefError));
      } catch (e) {
        failures.add('vault photos: ${_briefError(e)}');
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
      _showMessage('$summary$failed$extra');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteBackup() async {
    if (_busy) return;
    final target = await showDialog<_DeleteTarget>(
      context: context,
      builder: (_) => const _DeleteBackupDialog(),
    );
    if (target == null || !mounted) return;

    final allowed = await requirePinReauth(
      context: context,
      unlockVaultUseCase: widget.unlockVaultUseCase,
      pinValidator: widget.pinValidator,
      actionLabel: 'delete backup',
    );
    if (!allowed || !mounted) return;

    final device = target != _DeleteTarget.cloud;
    final cloud = target != _DeleteTarget.device;
    setState(() => _busy = true);
    try {
      await widget.chatBackup()?.deleteBackup(device: device, cloud: cloud);
      await widget.vaultPhotoBackup().deleteBackup(
        device: device,
        cloud: cloud,
      );
      if (device) {
        await widget.settingsRepository.setLastVaultPhotoBackupAt(null);
        await widget.settingsRepository.setLastVaultPhotoBackupVaultId(null);
      }
      await _load();
      _showMessage('Backup deleted.');
    } catch (e) {
      _showMessage('Delete failed: ${_briefError(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BaseScreenShell(
      title: 'Backup & restore',
      showDrawerMenu: false,
      drawerSelectedIndex: 6,
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                const SectionHeader('Status'),
                SettingsCard(
                  children: [
                    ValueListenableBuilder<BackupProgress?>(
                      valueListenable: backupProgress.state,
                      builder: (context, progress, _) {
                        if (progress == null) {
                          return _StatusSummary(
                            lastChat: _lastChatBackup,
                            lastPhoto: _lastPhotoBackup,
                            formatTime: _formatTime,
                          );
                        }
                        return _ProgressRow(progress: progress);
                      },
                    ),
                    ListTile(
                      leading: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.backup_outlined),
                      title: const Text('Back up now'),
                      subtitle: const Text(
                        'Runs automatically every night around 2 AM.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : _backUpNow,
                    ),
                  ],
                ),
                const SectionHeader('What to back up'),
                SettingsCard(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.chat_bubble_outline_rounded),
                      title: const Text('Chats'),
                      subtitle: const Text('Messages and chat history.'),
                      value: _chatsOn,
                      onChanged: _setChats,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.photo_library_outlined),
                      title: const Text('Vault photos'),
                      subtitle: const Text(
                        'Encrypted photos and thumbnails. Trashed photos are '
                        'not included.',
                      ),
                      value: _photosOn,
                      onChanged: _setPhotos,
                    ),
                  ],
                ),
                const SectionHeader('Where to back up'),
                SettingsCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.smartphone_outlined),
                      title: const Text('This device'),
                      subtitle: const Text(
                        'Always on. Kept after clearing app data.',
                      ),
                      trailing: Icon(
                        Icons.check_circle_outline_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.cloud_outlined),
                      title: const Text('Google Drive'),
                      subtitle: Text(
                        _cloudOn
                            ? 'Private app folder in your Drive. Used when '
                                  'this phone has no backup.'
                            : 'Off. Backups stay on this phone only.',
                      ),
                      value: _cloudOn,
                      onChanged: _setCloud,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.wifi_rounded),
                      title: const Text('Wi-Fi only'),
                      subtitle: const Text(
                        'Avoid mobile data for Google Drive backups.',
                      ),
                      value: _wifiOnly,
                      onChanged: _cloudOn ? _setWifiOnly : null,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.sd_storage_outlined),
                      title: const Text('External encrypted mirror'),
                      subtitle: const Text(
                        'Keep encrypted files under Android/media so they '
                        'survive reinstall.',
                      ),
                      value: _externalMirrorOn,
                      onChanged: _setExternalMirror,
                    ),
                  ],
                ),
                const SectionHeader('Manage'),
                SettingsCard(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.restore_rounded),
                      title: const Text('Restore from backup'),
                      subtitle: const Text(
                        'Bring back chats and photos from this phone or '
                        'Google Drive.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : _restore,
                    ),
                    ListTile(
                      leading: const Icon(Icons.cloud_download_outlined),
                      title: const Text('Recover a Google vault'),
                      subtitle: Text(
                        'Current mode: ${_mode?.title ?? 'not set'}. '
                        'Restore its key and set a PIN on this device.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : _recoverGoogleVault,
                    ),
                    ListTile(
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        'Delete backup',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: const Text(
                        'Remove the copy on this phone, on Google Drive, or both.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: _busy ? null : _deleteBackup,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _StatusSummary extends StatelessWidget {
  const _StatusSummary({
    required this.lastChat,
    required this.lastPhoto,
    required this.formatTime,
  });

  final DateTime? lastChat;
  final DateTime? lastPhoto;
  final String Function(DateTime) formatTime;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.history_rounded),
      title: const Text('Last backup'),
      subtitle: Text(
        'Chats: ${lastChat == null ? 'never' : formatTime(lastChat!)}\n'
        'Vault photos: ${lastPhoto == null ? 'never' : formatTime(lastPhoto!)}',
      ),
      isThreeLine: true,
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.progress});

  final BackupProgress progress;

  @override
  Widget build(BuildContext context) {
    final fraction = progress.fraction;
    final count = progress.total == null
        ? null
        : '${progress.done} of ${progress.total}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(progress.label)),
              if (count != null) Text(count),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          LinearProgressIndicator(value: fraction),
        ],
      ),
    );
  }
}

/// Explains what deleting does, then asks which copy to remove.
class _DeleteBackupDialog extends StatefulWidget {
  const _DeleteBackupDialog();

  @override
  State<_DeleteBackupDialog> createState() => _DeleteBackupDialogState();
}

class _DeleteBackupDialogState extends State<_DeleteBackupDialog> {
  _DeleteTarget _target = _DeleteTarget.device;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = {
      _DeleteTarget.device: ('This phone', Icons.smartphone_outlined),
      _DeleteTarget.cloud: ('Google Drive', Icons.cloud_outlined),
      _DeleteTarget.both: ('Both', Icons.delete_sweep_outlined),
    };
    return AlertDialog(
      icon: Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
      title: const Text('Delete backup?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'This permanently deletes the selected backup. It cannot be '
            'undone.\n\n'
            'Chats and photos on this phone are not affected. Without a '
            'backup you cannot restore them after reinstalling or clearing '
            'app data.\n\n'
            'Removing all vault photos does not clear the backup. Only this '
            'action does.',
          ),
          const SizedBox(height: AppSpacing.md),
          for (final entry in options.entries)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(entry.value.$2),
              title: Text(entry.value.$1),
              trailing: Icon(
                _target == entry.key
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: theme.colorScheme.primary,
              ),
              onTap: () => setState(() => _target = entry.key),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () => Navigator.of(context).pop(_target),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
