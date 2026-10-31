import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/core/presentation/theme/app_colors.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../../widgets/pin_reauth_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.mode,
    required this.settingsRepository,
    required this.unlockVaultUseCase,
    required this.pinValidator,
    required this.onSettingsChanged,
    this.chatBackupService,
    super.key,
  });
  final UserMode mode;
  final SettingsRepository settingsRepository;
  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;
  final Future<void> Function() onSettingsChanged;

  /// Lazily resolves the chat backup service (it touches Firebase), or null
  /// when chat is unavailable (local mode).
  final ChatBackupService Function()? chatBackupService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _autoLockOnBackground = true;
  bool _photoSyncEnabled = false;
  bool _wifiOnlyBackup = true;
  bool _externalStorageMirrorEnabled = true;
  bool _driveEncryptedBackupEnabled = false;
  AppThemePalette _themePalette = AppThemePalette.royalIndigo;
  String _themeMode = 'system';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final photoSync = await widget.settingsRepository.isPhotoSyncEnabled();
    final externalMirror = await widget.settingsRepository
        .isExternalStorageMirrorEnabled();
    final driveBackup = await widget.settingsRepository
        .isDriveEncryptedBackupEnabled();
    final autoLock = await widget.settingsRepository
        .isAutoLockOnBackgroundEnabled();
    final paletteId = await widget.settingsRepository.getThemePaletteId();
    final themeMode = await widget.settingsRepository.getThemeMode();
    if (!mounted) return;
    setState(() {
      _photoSyncEnabled = photoSync;
      _externalStorageMirrorEnabled = externalMirror;
      _driveEncryptedBackupEnabled = driveBackup;
      _autoLockOnBackground = autoLock;
      _themePalette = AppThemePalette.fromId(paletteId);
      _themeMode = switch (themeMode) {
        'light' || 'dark' => themeMode!,
        _ => 'system',
      };
    });
    await _loadChatBackupInfo();
  }

  ChatBackupService? _chatBackup() {
    try {
      return widget.chatBackupService?.call();
    } catch (_) {
      return null;
    }
  }

  DateTime? _lastChatBackup;
  bool _chatBackupBusy = false;

  Future<void> _loadChatBackupInfo() async {
    final backup = _chatBackup();
    if (backup == null) return;
    try {
      final last = await backup.lastBackupAt();
      final wifiOnly = await backup.isWifiOnly();
      if (!mounted) return;
      setState(() {
        _lastChatBackup = last;
        _wifiOnlyBackup = wifiOnly;
      });
    } catch (_) {}
  }

  static String _formatTime(DateTime at) {
    final l = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
  }

  Future<void> _backUpChatNow() async {
    final backup = _chatBackup();
    if (backup == null || _chatBackupBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _chatBackupBusy = true);
    try {
      final result = await backup.backupNow(interactive: true);
      final skipped = result.skipped.entries
          .map((e) => '${e.key}: ${e.value}')
          .join('; ');
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Backed up ${result.messageCount} messages to '
            '${result.savedTo.join(' and ')}.'
            '${skipped.isEmpty ? '' : ' Skipped $skipped'}',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Chat backup failed: $e')));
    } finally {
      if (mounted) setState(() => _chatBackupBusy = false);
      await _loadChatBackupInfo();
    }
  }

  Future<void> _restoreChatBackup() async {
    final backup = _chatBackup();
    if (backup == null || _chatBackupBusy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _chatBackupBusy = true);
    try {
      final snapshot = await backup.findLatestBackup(interactive: true);
      if (!mounted) return;
      if (snapshot == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No chat backup found.')),
        );
        return;
      }
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Restore chat backup?'),
          content: Text(
            'Backup from ${_formatTime(snapshot.backupAt)} on '
            '${snapshot.source} with ${snapshot.messageCount} messages. '
            'Messages already on this device are kept.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (ok != true) return;
      await backup.restore(snapshot);
      messenger.showSnackBar(
        SnackBar(content: Text('Restored ${snapshot.messageCount} messages.')),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    } finally {
      if (mounted) setState(() => _chatBackupBusy = false);
    }
  }

  Future<void> _selectPalette(AppThemePalette palette) async {
    if (_themePalette == palette) return;
    setState(() => _themePalette = palette);
    await widget.settingsRepository.setThemePaletteId(palette.id);
    await widget.onSettingsChanged();
  }

  Future<void> _selectThemeMode(String mode) async {
    if (_themeMode == mode) return;
    setState(() => _themeMode = mode);
    await widget.settingsRepository.setThemeMode(mode);
    await widget.onSettingsChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BaseScreenShell(
      title: 'Settings',
      drawerSelectedIndex: 5,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          const SectionHeader('Appearance'),
          SettingsCard(
            children: [
              Padding(
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
                        Icon(
                          Icons.palette_outlined,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Theme color',
                                style: theme.textTheme.titleSmall,
                              ),
                              Text(
                                _themePalette.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final palette in AppThemePalette.values)
                          _ThemePaletteChip(
                            palette: palette,
                            selected: _themePalette == palette,
                            onTap: () => _selectPalette(palette),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
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
                        Icon(
                          Icons.brightness_6_outlined,
                          color: cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Text(
                          'Appearance mode',
                          style: theme.textTheme.titleSmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'system',
                            icon: Icon(Icons.brightness_auto_rounded, size: 18),
                            label: Text('System'),
                          ),
                          ButtonSegment(
                            value: 'light',
                            icon: Icon(Icons.light_mode_outlined, size: 18),
                            label: Text('Light'),
                          ),
                          ButtonSegment(
                            value: 'dark',
                            icon: Icon(Icons.dark_mode_outlined, size: 18),
                            label: Text('Dark'),
                          ),
                        ],
                        selected: {_themeMode},
                        onSelectionChanged: (selection) {
                          if (selection.isNotEmpty) {
                            unawaited(_selectThemeMode(selection.first));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SectionHeader('Security'),
          SettingsCard(
            children: [
              _SettingsSwitch(
                icon: Icons.screen_lock_portrait_outlined,
                title: 'Auto-lock on background',
                subtitle:
                    'Lock the vault automatically after 10 seconds in the background.',
                value: _autoLockOnBackground,
                onChanged: (v) async {
                  setState(() => _autoLockOnBackground = v);
                  await widget.settingsRepository
                      .setAutoLockOnBackgroundEnabled(v);
                  await widget.onSettingsChanged();
                },
              ),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('Change app PIN'),
                subtitle: const Text(
                  'Re-authenticate before choosing a new PIN.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final allowed = await requirePinReauth(
                    context: context,
                    unlockVaultUseCase: widget.unlockVaultUseCase,
                    pinValidator: widget.pinValidator,
                    actionLabel: 'change your PIN',
                  );
                  if (!allowed || !context.mounted) return;
                  context.push('/settings/change-pin');
                },
              ),
            ],
          ),
          const SectionHeader('Backup & sync'),
          SettingsCard(
            children: [
              _SettingsSwitch(
                icon: Icons.cloud_sync_outlined,
                title: 'Photo sync',
                subtitle: 'Upload encrypted photo packages only when enabled.',
                value: _photoSyncEnabled,
                onChanged: (v) async {
                  if (!v) {
                    final allowed = await requirePinReauth(
                      context: context,
                      unlockVaultUseCase: widget.unlockVaultUseCase,
                      pinValidator: widget.pinValidator,
                      actionLabel: 'disable photo sync',
                    );
                    if (!allowed) return;
                  }
                  setState(() => _photoSyncEnabled = v);
                  await widget.settingsRepository.setPhotoSyncEnabled(v);
                  await widget.onSettingsChanged();
                },
              ),
              _SettingsSwitch(
                icon: Icons.sd_storage_outlined,
                title: 'External encrypted mirror',
                subtitle:
                    'Keep encrypted files and manifest under Android/media for reinstall recovery.',
                value: _externalStorageMirrorEnabled,
                onChanged: (v) async {
                  setState(() => _externalStorageMirrorEnabled = v);
                  await widget.settingsRepository
                      .setExternalStorageMirrorEnabled(v);
                  await widget.onSettingsChanged();
                },
              ),
              _SettingsSwitch(
                icon: Icons.drive_folder_upload_outlined,
                title: 'Google Drive encrypted package',
                subtitle: widget.mode == UserMode.googleEnabled
                    ? 'Back up encrypted objects, manifest, and wrapped key envelope.'
                    : 'Switch to Google mode below to enable Drive backup.',
                value: _driveEncryptedBackupEnabled,
                onChanged: widget.mode == UserMode.googleEnabled
                    ? (v) async {
                        if (!v) {
                          final allowed = await requirePinReauth(
                            context: context,
                            unlockVaultUseCase: widget.unlockVaultUseCase,
                            pinValidator: widget.pinValidator,
                            actionLabel: 'disable Drive backup',
                          );
                          if (!allowed) return;
                        }
                        setState(() => _driveEncryptedBackupEnabled = v);
                        await widget.settingsRepository
                            .setDriveEncryptedBackupEnabled(v);
                        await widget.onSettingsChanged();
                      }
                    : null,
              ),
            ],
          ),
          if (widget.chatBackupService != null) ...[
            const SectionHeader('Chat backup'),
            SettingsCard(
              children: [
                _SettingsSwitch(
                  icon: Icons.wifi_rounded,
                  title: 'Backup on Wi-Fi only',
                  subtitle: 'Avoid mobile data when nightly chat backups run.',
                  value: _wifiOnlyBackup,
                  onChanged: (v) {
                    setState(() => _wifiOnlyBackup = v);
                    final backup = _chatBackup();
                    if (backup != null) unawaited(backup.setWifiOnly(v));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Back up chats now'),
                  subtitle: Text(
                    _lastChatBackup == null
                        ? 'Never backed up. Runs nightly around 2 AM to this '
                              'device and Google Drive.'
                        : 'Last backup ${_formatTime(_lastChatBackup!)}. '
                              'Runs nightly around 2 AM.',
                  ),
                  trailing: _chatBackupBusy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.chevron_right_rounded),
                  onTap: _chatBackupBusy ? null : _backUpChatNow,
                ),
                ListTile(
                  leading: const Icon(Icons.restore_rounded),
                  title: const Text('Restore chat backup'),
                  subtitle: const Text(
                    'Bring back messages from this device or Google Drive.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _chatBackupBusy ? null : _restoreChatBackup,
                ),
              ],
            ),
          ],
          const SectionHeader('Account & restore'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Google mode & restore'),
                subtitle: Text('${widget.mode.title} · Manage cloud restore'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  final allowed = await requirePinReauth(
                    context: context,
                    unlockVaultUseCase: widget.unlockVaultUseCase,
                    pinValidator: widget.pinValidator,
                    actionLabel: 'open restore',
                  );
                  if (!allowed || !context.mounted) return;
                  context.push('/restore');
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ThemePaletteChip extends StatelessWidget {
  const _ThemePaletteChip({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AppThemePalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.55)
          : cs.surfaceContainerHighest.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(
          color: selected ? palette.seed : cs.outlineVariant,
          width: selected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: palette.seed,
                  shape: BoxShape.circle,
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Colors.white,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                palette.label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.onSurface : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
