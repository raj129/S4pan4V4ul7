import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../application/services/pin_validator.dart';
import '../../../application/usecases/unlock_vault_usecase.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../../core/widgets/base_screen_shell.dart';
import '../../../domain/entities/user_mode.dart';
import '../../../domain/repositories/settings_repository.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/pin_reauth_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.mode,
    required this.settingsRepository,
    required this.unlockVaultUseCase,
    required this.pinValidator,
    required this.onSettingsChanged,
    super.key,
  });
  final UserMode mode;
  final SettingsRepository settingsRepository;
  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;
  final Future<void> Function() onSettingsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _appLockOnOpen = true;
  bool _autoLockOnBackground = true;
  bool _photoSyncEnabled = false;
  bool _vmkBackupEnabled = false;
  bool _wifiOnlyBackup = true;
  bool _chargingOnlySync = false;
  bool _externalStorageMirrorEnabled = true;
  bool _driveEncryptedBackupEnabled = false;
  bool _preserveExif = false;
  bool _stripMetadataOnShare = true;
  bool _allowCameraImport = true;
  bool _allowShareIntentImport = true;

  @override
  void initState() {
    super.initState();
    _vmkBackupEnabled = widget.mode == UserMode.googleEnabled;
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final photoSync = await widget.settingsRepository.isPhotoSyncEnabled();
    final externalMirror = await widget.settingsRepository
        .isExternalStorageMirrorEnabled();
    final driveBackup = await widget.settingsRepository
        .isDriveEncryptedBackupEnabled();
    if (!mounted) return;
    setState(() {
      _photoSyncEnabled = photoSync;
      _externalStorageMirrorEnabled = externalMirror;
      _driveEncryptedBackupEnabled = driveBackup;
    });
  }

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;

    return BaseScreenShell(
      title: 'Settings',
      drawerSelectedIndex: 4,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          const SectionHeader('Security'),
          SettingsCard(
            children: [
              _SettingsSwitch(
                icon: Icons.lock_outline_rounded,
                title: 'Lock app on open',
                subtitle: 'Require your PIN each time the vault opens.',
                value: _appLockOnOpen,
                onChanged: (v) => setState(() => _appLockOnOpen = v),
              ),
              _SettingsSwitch(
                icon: Icons.screen_lock_portrait_outlined,
                title: 'Auto-lock on background',
                subtitle: 'Protect the vault when you leave the app.',
                value: _autoLockOnBackground,
                onChanged: (v) => setState(() => _autoLockOnBackground = v),
              ),
            ],
          ),
          const SectionHeader('Backup & sync'),
          SettingsCard(
            children: [
              _SettingsSwitch(
                icon: Icons.vpn_key_outlined,
                title: 'VMK backup',
                subtitle: widget.mode == UserMode.googleEnabled
                    ? 'Back up the wrapped vault master key for restore.'
                    : 'Switch to Google mode to enable key backup.',
                value: _vmkBackupEnabled,
                onChanged: widget.mode == UserMode.googleEnabled
                    ? (v) => setState(() => _vmkBackupEnabled = v)
                    : null,
              ),
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
                subtitle:
                    'Back up encrypted objects, manifest, and wrapped key envelope.',
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
              _SettingsSwitch(
                icon: Icons.wifi_rounded,
                title: 'Backup on Wi-Fi only',
                subtitle: 'Avoid mobile data when backup jobs run.',
                value: _wifiOnlyBackup,
                onChanged: (v) => setState(() => _wifiOnlyBackup = v),
              ),
              _SettingsSwitch(
                icon: Icons.battery_charging_full_rounded,
                title: 'Sync while charging only',
                subtitle: 'Defer sync jobs until the device is plugged in.',
                value: _chargingOnlySync,
                onChanged: (v) => setState(() => _chargingOnlySync = v),
              ),
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Sync now'),
                subtitle: const Text('Queue a manual encrypted backup sync.'),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Sync job queued.')),
                  );
                },
              ),
            ],
          ),
          const SectionHeader('Import & privacy'),
          SettingsCard(
            children: [
              _SettingsSwitch(
                icon: Icons.photo_camera_outlined,
                title: 'Allow camera import',
                subtitle: 'Let the app add new photos captured on-device.',
                value: _allowCameraImport,
                onChanged: (v) => setState(() => _allowCameraImport = v),
              ),
              _SettingsSwitch(
                icon: Icons.ios_share_outlined,
                title: 'Allow share-intent import',
                subtitle:
                    'Accept photos shared into the vault from other apps.',
                value: _allowShareIntentImport,
                onChanged: (v) => setState(() => _allowShareIntentImport = v),
              ),
              _SettingsSwitch(
                icon: Icons.badge_outlined,
                title: 'Preserve EXIF metadata',
                subtitle:
                    'Keep camera, location, and timestamp metadata on import.',
                value: _preserveExif,
                onChanged: (v) => setState(() => _preserveExif = v),
              ),
              _SettingsSwitch(
                icon: Icons.privacy_tip_outlined,
                title: 'Strip metadata on share',
                subtitle: 'Remove metadata when exporting a decrypted copy.',
                value: _stripMetadataOnShare,
                onChanged: (v) => setState(() => _stripMetadataOnShare = v),
              ),
            ],
          ),
          const SectionHeader('Vault & account'),
          SettingsCard(
            children: [
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('Change app PIN'),
                subtitle: const Text(
                  'Re-authenticate before choosing a new PIN.',
                ),
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
              ListTile(
                leading: const Icon(Icons.cloud_outlined),
                title: const Text('Google mode & restore'),
                subtitle: Text('${widget.mode.title} · Manage cloud restore'),
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
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: errorColor),
                title: Text('Reset vault', style: TextStyle(color: errorColor)),
                subtitle: const Text(
                  'Delete local vault data from this device.',
                ),
                onTap: () {},
              ),
            ],
          ),
        ],
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
