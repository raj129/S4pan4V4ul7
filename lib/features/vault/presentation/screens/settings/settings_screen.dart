import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:photo_vault/core/media/animated_media.dart';
import 'package:photo_vault/core/platform/hdr_preview_capability.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/core/platform/screenshot_protection.dart';
import 'package:photo_vault/core/presentation/theme/app_colors.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/platform/battery_optimization.dart';
import 'package:photo_vault/features/backup/application/backup_manager.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    required this.settingsRepository,
    required this.unlockVaultUseCase,
    required this.pinValidator,
    required this.onSettingsChanged,
    this.backupManager,
    this.screenshotProtection = const AndroidScreenshotProtection(),
    this.onShowLastSeenChanged,
    this.batteryOptimization = const AndroidBatteryOptimization(),
    super.key,
  });

  final SettingsRepository settingsRepository;
  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;
  final Future<void> Function() onSettingsChanged;
  final BackupManager? backupManager;
  final ScreenshotProtectionController screenshotProtection;

  /// Reports and requests exemption from Android battery optimisation.
  final BatteryOptimization batteryOptimization;

  /// Applies a "Show last seen" change to live presence (chat), if available.
  final Future<void> Function(bool show)? onShowLastSeenChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  MediaAnimationMode _motionPhotoMode =
      MediaAnimationPreference.instance.mode.value;
  bool _hdrPreviewEnabled = HdrPreviewPreference.instance.enabled.value;
  bool _autoLockOnBackground = true;
  int _autoLockTimeoutSeconds =
      SettingsRepository.defaultAutoLockTimeoutSeconds;
  bool _showLastSeen = true;
  bool _screenshotProtectionEnabled = true;
  bool? _backgroundAllowed;
  bool _loaded = false;

  Future<void> _loadBackgroundStatus() async {
    final allowed = await widget.batteryOptimization.isExempt();
    if (mounted) setState(() => _backgroundAllowed = allowed);
  }

  Future<void> _requestBackground() async {
    await ensureBackgroundAllowed(context, service: widget.batteryOptimization);
    await _loadBackgroundStatus();
  }

  AppThemePalette _themePalette = AppThemePalette.royalIndigo;
  String _themeMode = 'system';
  String? _version;

  @override
  void initState() {
    super.initState();
    HdrPreviewPreference.instance.configure(widget.settingsRepository);
    MediaAnimationPreference.instance.mode.addListener(
      _onMotionPhotoModeChanged,
    );
    HdrPreviewPreference.instance.enabled.addListener(_onHdrPreviewChanged);
    unawaited(HdrPreviewCapability.instance.load());
    unawaited(_loadMediaPreviewPreferences());
    unawaited(_loadSettings());
    unawaited(_loadAbout());
    unawaited(_loadBackgroundStatus());
    final manager = widget.backupManager;
    if (manager != null && !manager.isLoaded) {
      unawaited(manager.load());
    }
  }

  Future<void> _loadAbout() async {
    String version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version} (${info.buildNumber})';
    } catch (_) {
      version = 'Unknown';
    }
    if (!mounted) return;
    setState(() => _version = version);
  }

  Future<void> _loadSettings() async {
    await widget.settingsRepository.migrateLegacyPhotoSyncSetting();
    final autoLock = await widget.settingsRepository
        .isAutoLockOnBackgroundEnabled();
    final autoLockTimeoutSeconds = await widget.settingsRepository
        .getAutoLockTimeoutSeconds();
    final showLastSeen = await widget.settingsRepository
        .isShowLastSeenEnabled();
    final screenshotProtectionEnabled = await widget.settingsRepository
        .isScreenshotProtectionEnabled();
    final paletteId = await widget.settingsRepository.getThemePaletteId();
    final themeMode = await widget.settingsRepository.getThemeMode();
    if (!mounted) return;
    setState(() {
      _autoLockOnBackground = autoLock;
      _autoLockTimeoutSeconds = autoLockTimeoutSeconds;
      _showLastSeen = showLastSeen;
      _screenshotProtectionEnabled = screenshotProtectionEnabled;
      _themePalette = AppThemePalette.fromId(paletteId);
      _themeMode = switch (themeMode) {
        'light' || 'dark' => themeMode!,
        _ => 'system',
      };
      _loaded = true;
    });
  }

  @override
  void dispose() {
    MediaAnimationPreference.instance.mode.removeListener(
      _onMotionPhotoModeChanged,
    );
    HdrPreviewPreference.instance.enabled.removeListener(_onHdrPreviewChanged);
    super.dispose();
  }

  Future<void> _loadMediaPreviewPreferences() async {
    try {
      await Future.wait([
        MediaAnimationPreference.instance.load(),
        HdrPreviewPreference.instance.load(),
      ]);
    } catch (error) {
      debugPrint('Could not load media preview settings: $error');
    }
    if (!mounted) return;
    setState(() {
      _motionPhotoMode = MediaAnimationPreference.instance.mode.value;
      _hdrPreviewEnabled = HdrPreviewPreference.instance.enabled.value;
    });
  }

  void _onMotionPhotoModeChanged() {
    if (!mounted) return;
    setState(
      () => _motionPhotoMode = MediaAnimationPreference.instance.mode.value,
    );
  }

  void _onHdrPreviewChanged() {
    if (!mounted) return;
    setState(
      () => _hdrPreviewEnabled = HdrPreviewPreference.instance.enabled.value,
    );
  }

  Future<void> _setMotionPhotoMode(MediaAnimationMode mode) async {
    try {
      await MediaAnimationPreference.instance.setMode(mode);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save Motion Photo setting: $error')),
      );
    }
  }

  Future<void> _setHdrPreview(bool enabled) async {
    try {
      await HdrPreviewPreference.instance.setEnabled(enabled);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save HDR preview setting: $error')),
      );
    }
  }

  Future<void> _selectAutoLockTimeout(int seconds) async {
    if (_autoLockTimeoutSeconds == seconds) return;
    final previous = _autoLockTimeoutSeconds;
    setState(() => _autoLockTimeoutSeconds = seconds);
    try {
      await widget.settingsRepository.setAutoLockTimeoutSeconds(seconds);
    } catch (error) {
      if (!mounted) return;
      setState(() => _autoLockTimeoutSeconds = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save auto-lock delay: $error')),
      );
      return;
    }
    await widget.onSettingsChanged();
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
      drawerSelectedIndex: 6,
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                    'Lock the vault automatically while it stays in the background.',
                value: _autoLockOnBackground,
                onChanged: (v) async {
                  setState(() => _autoLockOnBackground = v);
                  await widget.settingsRepository
                      .setAutoLockOnBackgroundEnabled(v);
                  await widget.onSettingsChanged();
                },
              ),
              ListTile(
                enabled: _autoLockOnBackground,
                leading: const Icon(Icons.timer_outlined),
                title: const Text('Auto-lock delay'),
                subtitle: Text(
                  _autoLockOnBackground
                      ? 'Lock the vault after ${_autoLockTimeoutLabel(_autoLockTimeoutSeconds)} '
                            'in the background.'
                      : 'Turn on Auto-lock on background to choose a delay.',
                ),
                trailing: DropdownButton<int>(
                  key: const Key('auto-lock-timeout-dropdown'),
                  value: _autoLockTimeoutSeconds,
                  onChanged: _autoLockOnBackground
                      ? (seconds) {
                          if (seconds != null) {
                            unawaited(_selectAutoLockTimeout(seconds));
                          }
                        }
                      : null,
                  items: SettingsRepository.autoLockTimeoutOptionsSeconds
                      .map(
                        (seconds) => DropdownMenuItem<int>(
                          value: seconds,
                          child: Text(_autoLockTimeoutLabel(seconds)),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const Text('Change app PIN'),
                subtitle: const Text(
                  'Enter your current PIN, then choose a new one.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                // No extra re-auth here: step 1 of Change PIN already checks
                // the current PIN, and asking twice was confusing.
                onTap: () => unawaited(context.push('/settings/change-pin')),
              ),
            ],
          ),
          const SectionHeader('Privacy'),
          SettingsCard(
            children: [
              _SettingsSwitch(
                icon: Icons.visibility_outlined,
                title: 'Show last seen',
                subtitle: _showLastSeen
                    ? 'Contacts can see when you were last online.'
                    : "Hidden. You also won't see other people's last seen.",
                value: _showLastSeen,
                onChanged: (v) async {
                  setState(() => _showLastSeen = v);
                  await widget.settingsRepository.setShowLastSeenEnabled(v);
                  await widget.onShowLastSeenChanged?.call(v);
                },
              ),
              if (widget.screenshotProtection.isSupportedPlatform)
                _SettingsSwitch(
                  icon: Icons.no_photography_outlined,
                  title: 'Screenshot protection',
                  subtitle: _screenshotProtectionEnabled
                      ? 'Screenshots and screen recordings are blocked.'
                      : 'Screenshots and screen recordings are allowed.',
                  value: _screenshotProtectionEnabled,
                  onChanged: (enabled) async {
                    await widget.settingsRepository
                        .setScreenshotProtectionEnabled(enabled);
                    await widget.screenshotProtection.setEnabled(enabled);
                    if (mounted) {
                      setState(() => _screenshotProtectionEnabled = enabled);
                    }
                  },
                ),
            ],
          ),
          const SectionHeader('Notifications'),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('notification-settings-navigation-tile'),
                leading: const Icon(Icons.notifications_active_outlined),
                title: const Text('Notification settings'),
                subtitle: const Text(
                  'Configure chat, ring, and background location notifications.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => unawaited(context.push('/settings/notifications')),
              ),
            ],
          ),
          const SectionHeader('Backup & restore'),
          SettingsCard(
            children: [
              _BackupEntryTile(
                manager: widget.backupManager,
                onTap: () => unawaited(context.push('/settings/backup')),
              ),
              ListTile(
                leading: Icon(
                  _backgroundAllowed == false
                      ? Icons.battery_alert_outlined
                      : Icons.battery_charging_full_outlined,
                ),
                title: const Text('Run in background'),
                subtitle: Text(switch (_backgroundAllowed) {
                  null => 'Checking…',
                  true =>
                    'Allowed. Live location, alerts and backups keep running.',
                  false =>
                    'Restricted by battery saver. Tap to allow so background '
                        'tasks are not stopped.',
                }),
                trailing: _backgroundAllowed == false
                    ? const Icon(Icons.chevron_right_rounded)
                    : const Icon(Icons.check_circle_outline_rounded),
                onTap: _backgroundAllowed == false
                    ? () => unawaited(_requestBackground())
                    : null,
              ),
            ],
          ),
          const SectionHeader('Media preview'),
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
                    Text(
                      'Motion Photo playback',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      children: [
                        ChoiceChip(
                          key: const Key('motion-photo-loop-mode'),
                          avatar: const Icon(Icons.repeat_rounded, size: 18),
                          label: const Text('Loop'),
                          selected: _motionPhotoMode == MediaAnimationMode.loop,
                          onSelected: (_) => unawaited(
                            _setMotionPhotoMode(MediaAnimationMode.loop),
                          ),
                        ),
                        ChoiceChip(
                          key: const Key('motion-photo-once-mode'),
                          avatar: const Icon(
                            Icons.play_arrow_rounded,
                            size: 18,
                          ),
                          label: const Text('Play once'),
                          selected: _motionPhotoMode == MediaAnimationMode.once,
                          onSelected: (_) => unawaited(
                            _setMotionPhotoMode(MediaAnimationMode.once),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _motionPhotoMode == MediaAnimationMode.loop
                          ? 'Loop until paused in chat and vault.'
                          : 'Play once, then return to the still photo.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: HdrPreviewCapability.instance.available,
                builder: (context, isAvailable, _) => isAvailable
                    ? _SettingsSwitch(
                        icon: Icons.hdr_on_rounded,
                        title: 'HDR photo preview',
                        subtitle: _hdrPreviewEnabled
                            ? 'Use HDR rendering for supported photos.'
                            : 'Use the standard photo preview.',
                        value: _hdrPreviewEnabled,
                        onChanged: _setHdrPreview,
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          const SectionHeader('About'),
          SettingsCard(
            children: [
              ListTile(
                key: const Key('settings-version-tile'),
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Version'),
                subtitle: Text(_version ?? '…'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BackupEntryTile extends StatelessWidget {
  const _BackupEntryTile({required this.manager, required this.onTap});

  final BackupManager? manager;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final backup = manager;
    if (backup == null) {
      return ListTile(
        key: const Key('settings-backup-tile'),
        leading: const Icon(Icons.backup_outlined),
        title: const Text('Backup & restore'),
        subtitle: const Text(
          'Chats, vault photos, Google Drive, and vault recovery.',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
    }
    return ListenableBuilder(
      listenable: backup,
      builder: (context, _) => ListTile(
        key: const Key('settings-backup-tile'),
        leading: backup.isBusy
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.backup_outlined),
        title: const Text('Backup & restore'),
        subtitle: Text(backup.settingsSummary()),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

String _autoLockTimeoutLabel(int seconds) =>
    seconds == 60 ? '1 min' : '$seconds sec';

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
