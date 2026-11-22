import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/core/platform/battery_optimization.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';
import 'package:photo_vault/features/backup/application/backup_manager.dart';
import 'package:photo_vault/features/backup/application/backup_progress.dart';
import 'package:photo_vault/features/backup/application/vault_photo_backup_service.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/features/vault/presentation/widgets/pin_reauth_dialog.dart';

/// Every backup setting in one place: what to back up, where, live status and
/// progress, manual backup, restore, vault recovery, and delete.
class BackupScreen extends StatefulWidget {
  const BackupScreen({
    required this.settingsRepository,
    required this.chatBackup,
    required this.vaultPhotoBackup,
    required this.unlockVaultUseCase,
    required this.pinValidator,
    this.backupManager,
    this.authRepository,
    this.batteryOptimization = const AndroidBatteryOptimization(),
    super.key,
  });

  final SettingsRepository settingsRepository;

  /// Resolved lazily: chat touches Firebase and is unavailable in local mode.
  final ChatBackupService? Function() chatBackup;
  final VaultPhotoBackupService Function() vaultPhotoBackup;
  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;
  final BackupManager? backupManager;
  final AuthRepository? authRepository;
  final BatteryOptimization batteryOptimization;

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

enum _DeleteTarget { device, cloud, both }

class _BackupScreenState extends State<BackupScreen> {
  BackupManager? _ownedManager;
  late BackupManager _manager;
  bool? _backgroundAllowed;

  @override
  void initState() {
    super.initState();
    _attachManager();
    unawaited(_loadBackgroundStatus());
  }

  void _attachManager() {
    if (widget.backupManager != null) {
      _manager = widget.backupManager!;
    } else {
      _ownedManager = BackupManager(
        settingsRepository: widget.settingsRepository,
        chatBackup: widget.chatBackup,
        vaultPhotoBackup: widget.vaultPhotoBackup,
        authRepository: widget.authRepository,
      );
      _manager = _ownedManager!;
    }
    _manager.addListener(_onManagerChanged);
    unawaited(_manager.load());
  }

  @override
  void didUpdateWidget(covariant BackupScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backupManager != widget.backupManager) {
      _manager.removeListener(_onManagerChanged);
      _ownedManager?.dispose();
      _ownedManager = null;
      _attachManager();
    }
  }

  void _onManagerChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadBackgroundStatus() async {
    final allowed = await widget.batteryOptimization.isExempt();
    if (mounted) setState(() => _backgroundAllowed = allowed);
  }

  Future<void> _requestBackground() async {
    await ensureBackgroundAllowed(
      context,
      service: widget.batteryOptimization,
      reason: 'so automatic nightly backups can finish while the app is closed',
    );
    await _loadBackgroundStatus();
  }

  Future<void> _recoverGoogleVault() async {
    if (_manager.isBusy) return;
    final allowed = await requirePinReauth(
      context: context,
      unlockVaultUseCase: widget.unlockVaultUseCase,
      pinValidator: widget.pinValidator,
      actionLabel: 'recover a Google vault',
    );
    if (!allowed || !mounted) return;
    await context.push('/restore');
    if (mounted) unawaited(_manager.load());
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerChanged);
    _ownedManager?.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    if (_manager.isBusy) return;
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
    await _manager.restoreFromBackup();
  }

  Future<void> _deleteBackup() async {
    if (_manager.isBusy) return;
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
    await _manager.deleteBackup(device: device, cloud: cloud);
  }

  static InfoBannerTone _mapTone(BackupNoticeTone tone) => switch (tone) {
    BackupNoticeTone.info => InfoBannerTone.info,
    BackupNoticeTone.success => InfoBannerTone.success,
    BackupNoticeTone.warning => InfoBannerTone.warning,
    BackupNoticeTone.error => InfoBannerTone.error,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notice = _manager.lastNotice;
    final progress = _manager.progress;
    final busy = _manager.isBusy;

    return BaseScreenShell(
      title: 'Backup & restore',
      showDrawerMenu: false,
      drawerSelectedIndex: 6,
      body: !_manager.isLoaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              children: [
                if (_backgroundAllowed == false)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      0,
                    ),
                    child: InfoBanner(
                      key: const Key('backup-battery-warning-banner'),
                      tone: InfoBannerTone.warning,
                      icon: Icons.battery_alert_outlined,
                      title: 'Background backups restricted',
                      message:
                          'Battery saver may stop automatic 2 AM backups while '
                          'the app is closed.',
                      action: TextButton(
                        onPressed: () => unawaited(_requestBackground()),
                        child: const Text('Allow'),
                      ),
                    ),
                  ),
                if (notice != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      0,
                    ),
                    child: InfoBanner(
                      key: const Key('backup-status-notice-banner'),
                      tone: _mapTone(notice.tone),
                      message: notice.message,
                      action: IconButton(
                        tooltip: 'Dismiss',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: _manager.clearNotice,
                      ),
                    ),
                  ),
                const SectionHeader('Status'),
                SettingsCard(
                  children: [
                    if (progress != null)
                      _ProgressRow(progress: progress)
                    else if (busy)
                      _ProgressRow(
                        progress: BackupProgress(
                          label: _manager.settingsSummary(),
                        ),
                      )
                    else
                      _StatusSummary(
                        chatsEnabled: _manager.chatsEnabled,
                        photosEnabled: _manager.photosEnabled,
                        cloudEnabled: _manager.cloudEnabled,
                        wifiOnly: _manager.wifiOnly,
                        hasPendingCloud: _manager.hasPendingCloudUpload,
                        lastChat: _manager.lastChatBackupAt,
                        lastPhoto: _manager.lastPhotoBackupAt,
                        formatTime: BackupManager.formatTimestamp,
                      ),
                    ListTile(
                      leading: busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.backup_outlined),
                      title: const Text('Back up now'),
                      subtitle: const Text(
                        'Runs silently every night around 2 AM.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: busy ? null : () => unawaited(_manager.backUpNow()),
                    ),
                  ],
                ),
                const SectionHeader('What to back up'),
                SettingsCard(
                  children: [
                    SwitchListTile(
                      secondary: const Icon(Icons.chat_bubble_outline_rounded),
                      title: const Text('Chats'),
                      subtitle: const Text(
                        'Encrypted messages and chat history.',
                      ),
                      value: _manager.chatsEnabled,
                      onChanged: busy
                          ? null
                          : (v) => unawaited(_manager.setChatsEnabled(v)),
                    ),
                    SwitchListTile(
                      secondary: SettingsIconBadge(
                        icon: Icons.photo_library_outlined,
                        backgroundColor: theme.colorScheme.secondaryContainer,
                        iconColor: theme.colorScheme.onSecondaryContainer,
                      ),
                      title: const Text('Vault photos'),
                      subtitle: const Text(
                        'Encrypted photos and thumbnails. Trashed photos are '
                        'not included.',
                      ),
                      value: _manager.photosEnabled,
                      onChanged: busy
                          ? null
                          : (v) => unawaited(_manager.setPhotosEnabled(v)),
                    ),
                    SwitchListTile(
                      secondary: SettingsIconBadge(
                        icon: Icons.tune_rounded,
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        iconColor: theme.colorScheme.onTertiaryContainer,
                      ),
                      title: const Text('App settings'),
                      subtitle: const Text(
                        'Theme, security, privacy, and notification preferences.',
                      ),
                      value: _manager.settingsEnabled,
                      onChanged: busy
                          ? null
                          : (v) => unawaited(_manager.setSettingsEnabled(v)),
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
                        'Always on. Encrypted copy on this phone.',
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
                        _manager.cloudEnabled
                            ? 'Private app folder in your Drive. Used when '
                                  'this phone has no backup.'
                            : 'Off. Backups stay on this phone only.',
                      ),
                      value: _manager.cloudEnabled,
                      onChanged: busy
                          ? null
                          : (v) => unawaited(_manager.setCloudEnabled(v)),
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.wifi_rounded),
                      title: const Text('Wi-Fi only'),
                      subtitle: const Text(
                        'Avoid mobile data for Google Drive backups.',
                      ),
                      value: _manager.wifiOnly,
                      onChanged: (!busy && _manager.cloudEnabled)
                          ? (v) => unawaited(_manager.setWifiOnly(v))
                          : null,
                    ),
                    SwitchListTile(
                      secondary: const Icon(Icons.sd_storage_outlined),
                      title: const Text('External encrypted mirror'),
                      subtitle: const Text(
                        'Keep encrypted files under Android/media so they '
                        'survive reinstall.',
                      ),
                      value: _manager.externalMirrorEnabled,
                      onChanged: busy
                          ? null
                          : (v) => unawaited(
                              _manager.setExternalMirrorEnabled(v),
                            ),
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
                      onTap: busy ? null : _restore,
                    ),
                    ListTile(
                      leading: const Icon(Icons.cloud_download_outlined),
                      title: const Text('Recover a Google vault'),
                      subtitle: Text(
                        'Current mode: ${_manager.userMode?.title ?? 'not set'}. '
                        'Restore its key and set a PIN on this device.',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: busy ? null : _recoverGoogleVault,
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
                      onTap: busy ? null : _deleteBackup,
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
    required this.chatsEnabled,
    required this.photosEnabled,
    required this.cloudEnabled,
    required this.wifiOnly,
    required this.hasPendingCloud,
    required this.lastChat,
    required this.lastPhoto,
    required this.formatTime,
  });

  final bool chatsEnabled;
  final bool photosEnabled;
  final bool cloudEnabled;
  final bool wifiOnly;
  final bool hasPendingCloud;
  final DateTime? lastChat;
  final DateTime? lastPhoto;
  final String Function(DateTime) formatTime;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final anyOn = chatsEnabled || photosEnabled;
    final (icon, headline) = !anyOn
        ? (Icons.backup_table_outlined, 'Automatic backups are turned off')
        : hasPendingCloud
        ? (
            Icons.cloud_upload_outlined,
            wifiOnly
                ? 'Waiting for Wi-Fi to finish Drive upload'
                : 'Google Drive upload pending',
          )
        : cloudEnabled
        ? (
            Icons.cloud_done_outlined,
            'Protected on this device & Google Drive',
          )
        : (Icons.smartphone_outlined, 'Protected on this device only');

    final chatLine = !chatsEnabled
        ? 'Off'
        : (lastChat == null ? 'Not yet' : formatTime(lastChat!));
    final photoLine = !photosEnabled
        ? 'Off'
        : (lastPhoto == null ? 'Not yet' : formatTime(lastPhoto!));

    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(headline),
      subtitle: Text('Chats: $chatLine\nVault photos: $photoLine'),
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
