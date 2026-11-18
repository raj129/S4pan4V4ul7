import 'dart:async';
import 'dart:io';

import 'package:android_ring_alerts/android_ring_alerts.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:photo_vault/core/widgets/base_screen_shell.dart';

import '../../domain/entities/ring_alert_preferences.dart';
import '../../domain/repositories/ring_alert_preferences_repository.dart';

class RingAlertSettingsScreen extends StatefulWidget {
  const RingAlertSettingsScreen({
    required this.repository,
    required this.uid,
    this.onTestNotification,
    super.key,
  });

  final RingAlertPreferencesRepository repository;
  final String? uid;
  final Future<void> Function({required String title, required String body})?
  onTestNotification;

  @override
  State<RingAlertSettingsScreen> createState() =>
      _RingAlertSettingsScreenState();
}

class _RingAlertSettingsScreenState extends State<RingAlertSettingsScreen>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _notificationTitleController = TextEditingController();
  final _notificationBodyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _preferences.source == RingAlertSource.system) {
      unawaited(_refreshSystemSettings());
    }
  }

  RingAlertPreferences _preferences = const RingAlertPreferences();
  RingAlertPreferences _savedPreferences = const RingAlertPreferences();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  bool _hasFlashlight = false;
  bool _systemFlashEnabled = false;
  bool _cameraPermissionGranted = false;
  String? _error;
  String? _ringtoneTitle;
  String? _systemRingtoneTitle;

  bool get _hasUnsavedChanges => _preferences != _savedPreferences;

  void _stageContentDraft() {
    _stagePreferences(
      _preferences.copyWith(
        notificationTitle: _notificationTitleController.text.trim(),
        notificationBody: _notificationBodyController.text.trim(),
      ),
    );
  }

  void _stagePreferences(RingAlertPreferences next) {
    setState(() {
      if (next.ringtoneUri != _preferences.ringtoneUri) _ringtoneTitle = null;
      _preferences = next;
      _error = null;
    });
  }

  List<Widget> _buildHeaderActions() => [
    IconButton(
      key: const Key('save-ring-alert-settings-button'),
      tooltip: 'Save',
      onPressed: widget.uid == null || _saving || !_hasUnsavedChanges
          ? null
          : () => unawaited(_saveDraft()),
      icon: _saving
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.save_outlined),
    ),
    IconButton(
      key: const Key('revert-ring-alert-settings-button'),
      tooltip: 'Revert to saved',
      onPressed: _saving || !_hasUnsavedChanges ? null : _revertDraft,
      icon: const Icon(Icons.undo_rounded),
    ),
    IconButton(
      key: const Key('reset-ring-alert-settings-button'),
      tooltip: 'Reset notification',
      onPressed: widget.uid == null || _saving
          ? null
          : () => unawaited(_resetToDefaults()),
      icon: const Icon(Icons.restart_alt_rounded),
    ),
  ];

  Future<void> _load() async {
    final uid = widget.uid;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Sign in to chat to configure ring requests.';
      });
      return;
    }
    try {
      final settings = await widget.repository.getPreferences(uid);
      final title = settings.source == RingAlertSource.custom
          ? await AndroidRingAlerts.ringtoneTitle(settings.ringtoneUri)
          : null;
      final systemSettings = await AndroidRingAlerts.systemAlertSettings();
      final hasFlashlight = await AndroidRingAlerts.hasFlashlight();
      final cameraPermissionGranted = Platform.isAndroid
          ? (await Permission.camera.status).isGranted
          : false;
      if (!mounted) return;
      setState(() {
        _preferences = settings;
        _savedPreferences = settings;
        _notificationTitleController.text = settings.notificationTitle;
        _notificationBodyController.text = settings.notificationBody;
        _ringtoneTitle = title;
        _systemRingtoneTitle = systemSettings['ringtoneTitle'] as String?;
        _systemFlashEnabled = systemSettings['cameraFlashEnabled'] == true;
        _hasFlashlight = hasFlashlight;
        _cameraPermissionGranted = cameraPermissionGranted;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load ring-request settings: $error';
      });
    }
  }

  Future<void> _refreshSystemSettings() async {
    try {
      final settings = await AndroidRingAlerts.systemAlertSettings();
      final cameraPermissionGranted = Platform.isAndroid
          ? (await Permission.camera.status).isGranted
          : false;
      if (!mounted) return;
      setState(() {
        _systemRingtoneTitle = settings['ringtoneTitle'] as String?;
        _systemFlashEnabled = settings['cameraFlashEnabled'] == true;
        _cameraPermissionGranted = cameraPermissionGranted;
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Could not refresh system alert settings: $error',
        );
      }
    }
  }

  Future<void> _saveDraft() async {
    final uid = widget.uid;
    if (uid == null || _saving || !_hasUnsavedChanges) return;
    final previous = _savedPreferences;
    final next = _preferences;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.savePreferences(uid, next);
      if (!mounted) return;
      setState(() {
        _savedPreferences = next;
        _saving = false;
      });
      if (previous.enabled && !next.enabled) {
        try {
          await AndroidRingAlerts.stopAlert();
        } catch (error) {
          if (mounted) {
            setState(
              () => _error =
                  'Setting saved, but the active alert did not stop: $error',
            );
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ring request settings saved.')),
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not save ring-request settings: $error');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save ring-request settings: $error'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _revertDraft() {
    setState(() {
      _preferences = _savedPreferences;
      _notificationTitleController.text = _savedPreferences.notificationTitle;
      _notificationBodyController.text = _savedPreferences.notificationBody;
      _error = null;
    });
    if (_preferences.source == RingAlertSource.custom) {
      unawaited(_refreshRingtoneTitle());
    }
  }

  Future<void> _refreshRingtoneTitle() async {
    try {
      final title = await AndroidRingAlerts.ringtoneTitle(
        _preferences.ringtoneUri,
      );
      if (mounted) setState(() => _ringtoneTitle = title);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not load the selected ringtone: $error');
      }
    }
  }

  Future<void> _chooseRingtone() async {
    if (_preferences.source != RingAlertSource.custom) return;
    try {
      final uri = await AndroidRingAlerts.pickRingtone(
        currentUri: _preferences.ringtoneUri,
      );
      if (uri == null) return;
      final next = _preferences.copyWith(ringtoneUri: uri);
      _stagePreferences(next);
      final title = await AndroidRingAlerts.ringtoneTitle(uri);
      if (mounted) setState(() => _ringtoneTitle = title);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not choose ringtone: $error')),
        );
      }
    }
  }

  Future<void> _setFlashlightEnabled(bool enabled) async {
    if (_saving) return;
    if (enabled) {
      try {
        final permission = await Permission.camera.request();
        if (!permission.isGranted) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  permission.isPermanentlyDenied
                      ? 'Camera permission is required for flashlight alerts. '
                            'Enable it in app settings.'
                      : 'Camera permission is required for flashlight alerts.',
                ),
                action: permission.isPermanentlyDenied
                    ? SnackBarAction(
                        label: 'Settings',
                        onPressed: () => unawaited(openAppSettings()),
                      )
                    : null,
              ),
            );
          }
          return;
        }
        final available = await AndroidRingAlerts.hasFlashlight();
        if (!available) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'This phone does not have an available flashlight.',
                ),
              ),
            );
            setState(() => _hasFlashlight = false);
          }
          return;
        }
        if (mounted) setState(() => _hasFlashlight = true);
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not enable flashlight: $error')),
          );
        }
        return;
      }
    }
    _stagePreferences(_preferences.copyWith(flashlightEnabled: enabled));
  }

  Future<void> _testAlert() async {
    if (_testing) return;
    setState(() => _testing = true);
    try {
      await widget.onTestNotification?.call(
        title: _preferences.notificationTitle,
        body: _preferences.notificationBody,
      );
      final hasSelectedOutput =
          _preferences.source == RingAlertSource.system ||
          _preferences.ringSoundEnabled ||
          _preferences.vibrationEnabled ||
          _preferences.flashlightEnabled;
      if (!hasSelectedOutput) return;
      await AndroidRingAlerts.startAlert(
        alertId: 'ring-test-${DateTime.now().millisecondsSinceEpoch}',
        source: _preferences.source.name,
        ringSoundEnabled: _preferences.ringSoundEnabled,
        vibrationEnabled: _preferences.vibrationEnabled,
        timeoutSeconds: _preferences.timeoutSeconds,
        title: 'Ring request test',
        body: 'Testing your ring-request alert settings.',
        ringtoneUri: _preferences.ringtoneUri,
        vibrationPattern: _preferences.vibrationPattern.name,
        flashlightEnabled: _preferences.flashlightEnabled && _hasFlashlight,
        flashPattern: _preferences.flashPattern.name,
        startDelaySeconds: _preferences.testDelaySeconds,
        allowFlashInBackground: true,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start test alert: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset ring request settings?'),
        content: const Text(
          'This stages the default settings. Save to apply them.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _saving) return;
    const defaults = RingAlertPreferences();
    setState(() {
      _preferences = defaults;
      _notificationTitleController.text = defaults.notificationTitle;
      _notificationBodyController.text = defaults.notificationBody;
      _ringtoneTitle = null;
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Defaults staged. Save to apply.')),
    );
  }

  Future<void> _openSystemSoundSettings() async {
    try {
      await AndroidRingAlerts.openSystemRingtoneSettings();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open sound settings: $error')),
        );
      }
    }
  }

  Future<void> _openSystemFlashSettings() async {
    try {
      if (_systemFlashEnabled && !_cameraPermissionGranted) {
        final permission = await Permission.camera.request();
        if (permission.isGranted) {
          if (mounted) setState(() => _cameraPermissionGranted = true);
          return;
        }
        if (permission.isPermanentlyDenied) {
          await openAppSettings();
          return;
        }
      }
      await AndroidRingAlerts.openSystemFlashSettings();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open accessibility settings: $error'),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _notificationTitleController.dispose();
    _notificationBodyController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uid = widget.uid;
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : uid == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                _error ?? 'Sign in to chat to configure ring requests.',
              ),
            ),
          )
        : _buildSettings(context);
    return BaseScreenShell(
      title: 'Ring requests',
      showDrawerMenu: false,
      drawerSelectedIndex: 6,
      scaffoldKey: _scaffoldKey,
      actions: _buildHeaderActions(),
      body: body,
    );
  }

  Widget _buildSettings(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Ring requests are currently available on Android.'),
        ),
      );
    }
    final preference = _preferences;
    return ListView(
      children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        SwitchListTile(
          title: const Text('Allow ring requests'),
          subtitle: Text(
            preference.enabled
                ? 'Incoming ring requests use the settings below.'
                : 'Requests remain in chats, but will not alert you.',
          ),
          value: preference.enabled,
          onChanged: _saving
              ? null
              : (enabled) =>
                    _stagePreferences(preference.copyWith(enabled: enabled)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            'Notification content',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            key: const Key('ring-alert-title-field'),
            controller: _notificationTitleController,
            maxLength: 80,
            decoration: const InputDecoration(
              labelText: 'Notification header',
              helperText: 'Leave blank to hide the header.',
            ),
            onChanged: (_) => _stageContentDraft(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            key: const Key('ring-alert-body-field'),
            controller: _notificationBodyController,
            maxLength: 240,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Notification message',
              helperText: 'Leave blank for no message.',
            ),
            onChanged: (_) => _stageContentDraft(),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            'Alert behavior',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        RadioGroup<RingAlertSource>(
          groupValue: preference.source,
          onChanged: (source) => source == null
              ? null
              : _stagePreferences(preference.copyWith(source: source)),
          child: Column(
            children: [
              RadioListTile<RingAlertSource>(
                title: const Text('Follow system'),
                subtitle: const Text(
                  'Use phone sound, vibration, and flash-notification settings.',
                ),
                value: RingAlertSource.system,
                enabled: !_saving,
              ),
              RadioListTile<RingAlertSource>(
                title: const Text('Use app settings'),
                subtitle: const Text(
                  'Use these choices; Do Not Disturb and Android restrictions '
                  'still apply.',
                ),
                value: RingAlertSource.custom,
                enabled: !_saving,
              ),
            ],
          ),
        ),
        if (preference.source == RingAlertSource.system) ...[
          ListTile(
            leading: const Icon(Icons.music_note_rounded),
            title: const Text('System ringtone'),
            subtitle: Text(
              '${_systemRingtoneTitle ?? 'Phone default ringtone'} · Tap to change',
            ),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: _openSystemSoundSettings,
          ),
          ListTile(
            leading: const Icon(Icons.flash_on_outlined),
            title: const Text('System flashlight alerts'),
            subtitle: Text(
              _systemFlashEnabled && !_cameraPermissionGranted
                  ? 'Enabled in Android settings; allow camera access to use it'
                  : '${_systemFlashEnabled ? 'On' : 'Off'} in Android settings · '
                        'Tap to change',
            ),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: _openSystemFlashSettings,
          ),
        ],
        if (preference.source == RingAlertSource.custom) ...[
          SwitchListTile(
            title: const Text('Ring'),
            value: preference.ringSoundEnabled,
            onChanged: _saving
                ? null
                : (enabled) => _stagePreferences(
                    preference.copyWith(ringSoundEnabled: enabled),
                  ),
          ),
          if (preference.ringSoundEnabled)
            ListTile(
              leading: const Icon(Icons.music_note_rounded),
              title: const Text('Ringtone'),
              subtitle: Text(
                _ringtoneTitle ??
                    (preference.ringtoneUri == null
                        ? 'Phone default ringtone'
                        : 'Selected ringtone'),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _saving ? null : _chooseRingtone,
            ),
          SwitchListTile(
            title: const Text('Vibrate'),
            value: preference.vibrationEnabled,
            onChanged: _saving
                ? null
                : (enabled) => _stagePreferences(
                    preference.copyWith(vibrationEnabled: enabled),
                  ),
          ),
        ],
        if (preference.source == RingAlertSource.custom &&
            preference.vibrationEnabled)
          ListTile(
            title: const Text('Vibration pattern'),
            trailing: DropdownButton<RingVibrationPattern>(
              value: preference.vibrationPattern,
              onChanged: _saving
                  ? null
                  : (pattern) {
                      if (pattern != null) {
                        _stagePreferences(
                          preference.copyWith(vibrationPattern: pattern),
                        );
                      }
                    },
              items: const [
                DropdownMenuItem(
                  value: RingVibrationPattern.standard,
                  child: Text('Standard'),
                ),
                DropdownMenuItem(
                  value: RingVibrationPattern.shortPulses,
                  child: Text('Short pulses'),
                ),
                DropdownMenuItem(
                  value: RingVibrationPattern.longPulses,
                  child: Text('Long pulses'),
                ),
              ],
            ),
          ),
        if (preference.source == RingAlertSource.custom)
          SwitchListTile(
            title: const Text('Flashlight blink'),
            subtitle: Text(
              !_hasFlashlight
                  ? 'Requires camera permission and flashlight hardware.'
                  : preference.flashlightEnabled
                  ? 'Android 14+ cannot start flashlight alerts from background.'
                  : 'Off by default. Requires a phone flashlight.',
            ),
            value: preference.flashlightEnabled,
            onChanged: _saving ? null : _setFlashlightEnabled,
          ),
        if (preference.source == RingAlertSource.custom &&
            preference.flashlightEnabled)
          ListTile(
            title: const Text('Flash pattern'),
            trailing: DropdownButton<RingFlashPattern>(
              value: preference.flashPattern,
              onChanged: _saving
                  ? null
                  : (pattern) {
                      if (pattern != null) {
                        _stagePreferences(
                          preference.copyWith(flashPattern: pattern),
                        );
                      }
                    },
              items: const [
                DropdownMenuItem(
                  value: RingFlashPattern.slowBlink,
                  child: Text('Slow blink'),
                ),
                DropdownMenuItem(
                  value: RingFlashPattern.doubleBlink,
                  child: Text('Double blink'),
                ),
                DropdownMenuItem(
                  value: RingFlashPattern.fastBlink,
                  child: Text('Fast blink'),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            'Alert timing',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        ListTile(
          title: const Text('Alert timeout'),
          subtitle: const Text(
            'Stop ringing after this duration. Default: 15 seconds.',
          ),
          trailing: DropdownButton<int>(
            value: preference.timeoutSeconds,
            onChanged: _saving
                ? null
                : (seconds) {
                    if (seconds != null) {
                      _stagePreferences(
                        preference.copyWith(timeoutSeconds: seconds),
                      );
                    }
                  },
            items: [
              for (final seconds in RingAlertPreferences.timeoutOptionsSeconds)
                DropdownMenuItem(
                  value: seconds,
                  child: Text('$seconds seconds'),
                ),
            ],
          ),
        ),
        ListTile(
          title: const Text('Test delay'),
          subtitle: const Text('Wait before the settings test alert starts.'),
          trailing: DropdownButton<int>(
            value: preference.testDelaySeconds,
            onChanged: _saving
                ? null
                : (seconds) {
                    if (seconds != null) {
                      _stagePreferences(
                        preference.copyWith(testDelaySeconds: seconds),
                      );
                    }
                  },
            items: [
              for (final seconds
                  in RingAlertPreferences.testDelayOptionsSeconds)
                DropdownMenuItem(
                  value: seconds,
                  child: Text('$seconds seconds'),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: FilledButton.icon(
            onPressed: _testing || _saving
                ? null
                : () => unawaited(_testAlert()),
            icon: _testing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined),
            label: Text(
              preference.testDelaySeconds == 0
                  ? 'Test alert for ${preference.timeoutSeconds} seconds'
                  : 'Test in ${preference.testDelaySeconds} seconds for '
                        '${preference.timeoutSeconds} seconds',
            ),
          ),
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}
