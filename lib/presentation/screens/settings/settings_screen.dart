import 'package:flutter/material.dart';

import '../../../domain/entities/user_mode.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({required this.mode, super.key});
  final UserMode mode;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _appLockOnOpen = true;
  bool _autoLockOnBackground = true;
  bool _biometricUnlock = false;
  bool _photoSyncEnabled = false;
  bool _vmkBackupEnabled = false;
  bool _wifiOnlyBackup = true;
  bool _chargingOnlySync = false;
  bool _preserveExif = false;
  bool _stripMetadataOnShare = true;
  bool _allowCameraImport = true;
  bool _allowShareIntentImport = true;

  @override
  void initState() {
    super.initState();
    _vmkBackupEnabled = widget.mode == UserMode.googleEnabled;
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
            subtitle: const Text('Require PIN/biometric whenever app opens'),
            value: _appLockOnOpen,
            onChanged: (v) => setState(() => _appLockOnOpen = v),
          ),
          SwitchListTile(
            title: const Text('Auto-lock on background'),
            subtitle: const Text('Lock vault when app goes to background'),
            value: _autoLockOnBackground,
            onChanged: (v) => setState(() => _autoLockOnBackground = v),
          ),
          SwitchListTile(
            title: const Text('Biometric unlock'),
            subtitle: const Text('Convenience unlock (PIN remains required fallback)'),
            value: _biometricUnlock,
            onChanged: (v) => setState(() => _biometricUnlock = v),
          ),
          const Divider(height: 1),
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
            onChanged: (v) => setState(() => _photoSyncEnabled = v),
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
            onTap: () {},
          ),
          ListTile(
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Google mode & restore'),
            subtitle: Text(widget.mode.title),
            onTap: () {},
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
