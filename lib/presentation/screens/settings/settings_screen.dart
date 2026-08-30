import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../application/services/pin_validator.dart';
import '../../../application/usecases/unlock_vault_usecase.dart';
import '../../../domain/entities/user_mode.dart';
import '../../../domain/repositories/settings_repository.dart';
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
    final externalMirror =
        await widget.settingsRepository.isExternalStorageMirrorEnabled();
    final driveBackup =
        await widget.settingsRepository.isDriveEncryptedBackupEnabled();
    if (!mounted) return;
    setState(() {
      _photoSyncEnabled = photoSync;
      _externalStorageMirrorEnabled = externalMirror;
      _driveEncryptedBackupEnabled = driveBackup;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Security'),
          SwitchListTile(
            title: const Text('Lock app on open'),
            subtitle: const Text('Require PIN whenever app opens'),
            value: _appLockOnOpen,
            onChanged: (v) => setState(() => _appLockOnOpen = v),
          ),
          SwitchListTile(
            title: const Text('Auto-lock on background'),
            subtitle: const Text('Lock vault when app goes to background'),
            value: _autoLockOnBackground,
            onChanged: (v) => setState(() => _autoLockOnBackground = v),
          ),
          const _SectionHeader('Backup & Sync'),
          SwitchListTile(
            title: const Text('VMK backup'),
            subtitle: Text(
              widget.mode == UserMode.googleEnabled
                  ? 'Encrypted VMK backup is enabled in Google mode'
                  : 'Enable Google mode to use backup',
            ),
            value: _vmkBackupEnabled,
            onChanged: widget.mode == UserMode.googleEnabled
                ? (v) => setState(() => _vmkBackupEnabled = v)
                : null,
          ),
          SwitchListTile(
            title: const Text('Photo sync'),
            subtitle: const Text('Disabled by default; enable explicitly'),
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
          SwitchListTile(
            title: const Text('Keep encrypted copy in external storage'),
            subtitle: const Text(
              'Stores encrypted files + manifest under Android/media for recovery after reinstall.',
            ),
            value: _externalStorageMirrorEnabled,
            onChanged: (v) async {
              setState(() => _externalStorageMirrorEnabled = v);
              await widget.settingsRepository.setExternalStorageMirrorEnabled(v);
              await widget.onSettingsChanged();
            },
          ),
          SwitchListTile(
            title: const Text('Upload encrypted package to Google Drive'),
            subtitle: const Text(
              'Uploads encrypted objects + manifest + wrapped VMK envelope.',
            ),
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
          SwitchListTile(
            title: const Text('Backup on Wi-Fi only'),
            value: _wifiOnlyBackup,
            onChanged: (v) => setState(() => _wifiOnlyBackup = v),
          ),
          SwitchListTile(
            title: const Text('Sync while charging only'),
            value: _chargingOnlySync,
            onChanged: (v) => setState(() => _chargingOnlySync = v),
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Sync now'),
            subtitle: const Text('Manual sync trigger'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Sync job queued.')),
              );
            },
          ),
          const Divider(height: 1),
          const _SectionHeader('Import & Privacy'),
          SwitchListTile(
            title: const Text('Allow camera import'),
            value: _allowCameraImport,
            onChanged: (v) => setState(() => _allowCameraImport = v),
          ),
          SwitchListTile(
            title: const Text('Allow share-intent import'),
            value: _allowShareIntentImport,
            onChanged: (v) => setState(() => _allowShareIntentImport = v),
          ),
          SwitchListTile(
            title: const Text('Preserve EXIF metadata on import'),
            value: _preserveExif,
            onChanged: (v) => setState(() => _preserveExif = v),
          ),
          SwitchListTile(
            title: const Text('Strip metadata on decrypted share'),
            value: _stripMetadataOnShare,
            onChanged: (v) => setState(() => _stripMetadataOnShare = v),
          ),
          const Divider(height: 1),
          const _SectionHeader('Vault & Account'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Change app PIN'),
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
            subtitle: Text(widget.mode.title),
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
            leading: const Icon(Icons.delete_forever_outlined),
            title: const Text('Reset vault'),
            onTap: () {},
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
