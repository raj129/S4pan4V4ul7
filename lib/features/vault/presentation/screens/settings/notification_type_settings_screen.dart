import 'dart:async';
import 'dart:io';

import 'package:android_ring_alerts/android_ring_alerts.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:photo_vault/features/chat/application/services/chat_notification_service.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';
import 'package:photo_vault/features/vault/domain/entities/incoming_chat_alert_preferences.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

enum NotificationConfigurationType { chatMessages, backgroundLocation }

typedef ChatNotificationTester =
    Future<void> Function({
      required String title,
      required String body,
      required IncomingChatAlertPreferences preferences,
    });

typedef BackgroundLocationNotificationTester =
    Future<void> Function({required String title, required String body});

class NotificationTypeSettingsScreen extends StatefulWidget {
  const NotificationTypeSettingsScreen({
    required this.type,
    required this.settingsRepository,
    this.onTestChatNotification,
    this.onTestBackgroundLocation,
    this.onNotificationSettingsChanged,
    super.key,
  });

  final NotificationConfigurationType type;
  final SettingsRepository settingsRepository;
  final ChatNotificationTester? onTestChatNotification;
  final BackgroundLocationNotificationTester? onTestBackgroundLocation;
  final Future<void> Function()? onNotificationSettingsChanged;

  @override
  State<NotificationTypeSettingsScreen> createState() =>
      _NotificationTypeSettingsScreenState();
}

class _NotificationTypeSettingsScreenState
    extends State<NotificationTypeSettingsScreen>
    with WidgetsBindingObserver {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _headerController = TextEditingController();
  final _messageController = TextEditingController();
  String _savedHeader = '';
  String _savedMessage = '';
  IncomingChatAlertPreferences _savedChatAlertPreferences =
      const IncomingChatAlertPreferences();
  bool _loading = true;
  bool _saving = false;
  bool _testing = false;
  Timer? _delayedTestTimer;
  IncomingChatAlertPreferences _chatAlertPreferences =
      const IncomingChatAlertPreferences();
  String? _systemNotificationSoundTitle;
  String? _chatNotificationSoundTitle;
  bool _systemFlashEnabled = false;
  bool _hasFlashlight = false;
  bool _cameraPermissionGranted = false;
  String? _loadError;
  String? _saveError;

  bool get _isChat => widget.type == NotificationConfigurationType.chatMessages;
  bool get _hasUnsavedChanges =>
      _headerController.text.trim() != _savedHeader ||
      _messageController.text.trim() != _savedMessage ||
      (_isChat && _chatAlertPreferences != _savedChatAlertPreferences);
  String get _screenTitle => _isChat ? 'Chat messages' : 'Background location';
  String get _typeKey => _isChat ? 'incoming-chat' : 'background-location';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _isChat &&
        _chatAlertPreferences.source == NotificationAlertSource.system) {
      unawaited(_loadChatSystemSettings());
    }
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      if (_isChat) {
        final values = await Future.wait<Object>([
          widget.settingsRepository.getIncomingChatAlertTitle(),
          widget.settingsRepository.getIncomingChatAlertText(),
          widget.settingsRepository.getIncomingChatAlertPreferences(),
        ]);
        if (!mounted) return;
        setState(() {
          _headerController.text = values[0] as String;
          _messageController.text = values[1] as String;
          _chatAlertPreferences = values[2] as IncomingChatAlertPreferences;
          _savedHeader = _headerController.text.trim();
          _savedMessage = _messageController.text.trim();
          _savedChatAlertPreferences = _chatAlertPreferences;
          _loading = false;
        });
        unawaited(_loadChatSystemSettings());
      } else {
        final values = await Future.wait([
          widget.settingsRepository.getBackgroundLocationAlertTitle(),
          widget.settingsRepository.getBackgroundLocationAlertText(),
        ]);
        if (!mounted) return;
        setState(() {
          _headerController.text = values[0];
          _messageController.text = values[1];
          _savedHeader = _headerController.text.trim();
          _savedMessage = _messageController.text.trim();
          _loading = false;
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = 'Could not load notification settings: $error';
      });
    }
  }

  @override
  void dispose() {
    _delayedTestTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _headerController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _onDraftChanged() {
    setState(() => _saveError = null);
  }

  Future<void> _saveDraft() async {
    if (!_hasUnsavedChanges || _saving) return;
    final header = _headerController.text.trim();
    final message = _messageController.text.trim();
    final preferences = _chatAlertPreferences;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      if (_isChat) {
        await widget.settingsRepository.setIncomingChatAlertTitle(header);
        await widget.settingsRepository.setIncomingChatAlertText(message);
        await widget.settingsRepository.setIncomingChatAlertPreferences(
          preferences,
        );
      } else {
        await widget.settingsRepository.setBackgroundLocationAlertTitle(header);
        await widget.settingsRepository.setBackgroundLocationAlertText(message);
      }
      String? refreshError;
      if (!_isChat) {
        try {
          await widget.onNotificationSettingsChanged?.call();
        } catch (error) {
          refreshError = '$error';
        }
      }
      if (!mounted) return;
      setState(() {
        _savedHeader = header;
        _savedMessage = message;
        if (_isChat) _savedChatAlertPreferences = preferences;
        _saving = false;
        _saveError = refreshError == null
            ? null
            : 'Settings saved, but the live notification could not be '
                  'refreshed: $refreshError';
      });
      if (refreshError == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification settings saved.')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_saveError!)));
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _saveError = 'Could not save notification settings.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save notification settings: $error'),
          ),
        );
      }
    }
  }

  void _revertDraft() {
    setState(() {
      _headerController.text = _savedHeader;
      _messageController.text = _savedMessage;
      _chatAlertPreferences = _savedChatAlertPreferences;
      _saveError = null;
      if (_chatAlertPreferences.notificationSoundUri == null) {
        _chatNotificationSoundTitle = null;
      }
    });
    if (_isChat) unawaited(_loadChatSystemSettings());
  }

  Future<void> _loadChatSystemSettings() async {
    try {
      final settings = await AndroidRingAlerts.systemAlertSettings();
      final chatNotificationSoundTitle =
          _chatAlertPreferences.source == NotificationAlertSource.custom
          ? await AndroidRingAlerts.ringtoneTitle(
              _chatAlertPreferences.notificationSoundUri,
            )
          : null;
      final hasFlashlight = await AndroidRingAlerts.hasFlashlight();
      final cameraPermissionGranted = Platform.isAndroid
          ? (await Permission.camera.status).isGranted
          : false;
      if (!mounted) return;
      setState(() {
        _systemNotificationSoundTitle =
            settings['notificationSoundTitle'] as String?;
        _chatNotificationSoundTitle = chatNotificationSoundTitle;
        _systemFlashEnabled = settings['cameraFlashEnabled'] == true;
        _hasFlashlight = hasFlashlight;
        _cameraPermissionGranted = cameraPermissionGranted;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not read system alert settings: $error'),
          ),
        );
      }
    }
  }

  void _stageChatAlertPreferences(IncomingChatAlertPreferences next) {
    setState(() {
      if (next.notificationSoundUri !=
          _chatAlertPreferences.notificationSoundUri) {
        _chatNotificationSoundTitle = null;
      }
      _chatAlertPreferences = next;
      _saveError = null;
    });
  }

  Future<void> _chooseChatRingtone() async {
    try {
      final uri = await AndroidRingAlerts.pickNotificationSound(
        currentUri: _chatAlertPreferences.notificationSoundUri,
      );
      if (uri == null) return;
      _stageChatAlertPreferences(
        _chatAlertPreferences.copyWith(notificationSoundUri: uri),
      );
      final title = await AndroidRingAlerts.ringtoneTitle(uri);
      if (mounted) setState(() => _chatNotificationSoundTitle = title);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not choose ringtone: $error')),
        );
      }
    }
  }

  Future<void> _setChatFlashlight(bool enabled) async {
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
          }
          return;
        }
        if (mounted) {
          setState(() {
            _cameraPermissionGranted = true;
            _hasFlashlight = true;
          });
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not enable flashlight: $error')),
          );
        }
        return;
      }
    }
    _stageChatAlertPreferences(
      _chatAlertPreferences.copyWith(flashlightEnabled: enabled),
    );
  }

  Future<void> _openSystemSoundSettings() async {
    try {
      await AndroidRingAlerts.openNotificationChannelSettings(
        ChatNotificationService.systemChannelId,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not open notification settings: $error'),
          ),
        );
      }
    }
  }

  Future<void> _openSystemFlashSettings() async {
    try {
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

  Future<void> _testNotification({Duration delay = Duration.zero}) async {
    if (_testing || _saving) return;
    setState(() => _testing = true);
    if (delay > Duration.zero) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Sending test notification in ${delay.inSeconds}s. '
              'Lock your phone now to test watch alerts.',
            ),
          ),
        );
      }
      final completer = Completer<void>();
      _delayedTestTimer?.cancel();
      _delayedTestTimer = Timer(delay, completer.complete);
      await completer.future;
      if (!mounted) return;
    }
    try {
      if (_isChat) {
        final tester = widget.onTestChatNotification;
        if (tester == null) {
          throw StateError('Chat notification test unavailable.');
        }
        await tester(
          title: _headerController.text.trim(),
          body: _messageController.text.trim(),
          preferences: _chatAlertPreferences,
        );
      } else {
        final tester = widget.onTestBackgroundLocation;
        if (tester == null) {
          throw StateError('Background location preview unavailable.');
        }
        await tester(
          title: _headerController.text.trim(),
          body: _messageController.text.trim(),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test notification sent.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send test notification: $error')),
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
        title: const Text('Reset notification settings?'),
        content: Text(
          'This stages default settings for $_screenTitle. Save to apply them.',
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _saveError = null;
      _headerController.text = _isChat
          ? SettingsRepository.defaultIncomingChatAlertTitle
          : SettingsRepository.defaultBackgroundLocationAlertTitle;
      _messageController.text = _isChat
          ? SettingsRepository.defaultIncomingChatAlertText
          : SettingsRepository.defaultBackgroundLocationAlertText;
      if (_isChat) {
        _chatAlertPreferences = const IncomingChatAlertPreferences();
        _chatNotificationSoundTitle = null;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Defaults staged. Save to apply.')),
    );
  }

  List<Widget> _buildHeaderActions() => [
    IconButton(
      key: Key('save-$_typeKey-notification-button'),
      tooltip: 'Save',
      onPressed: _saving || !_hasUnsavedChanges
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
      key: Key('revert-$_typeKey-notification-button'),
      tooltip: 'Revert to saved',
      onPressed: _saving || !_hasUnsavedChanges ? null : _revertDraft,
      icon: const Icon(Icons.undo_rounded),
    ),
    IconButton(
      key: Key('reset-$_typeKey-notification-button'),
      tooltip: 'Reset notification',
      onPressed: _saving ? null : () => unawaited(_resetToDefaults()),
      icon: const Icon(Icons.restart_alt_rounded),
    ),
  ];

  @override
  Widget build(BuildContext context) => BaseScreenShell(
    title: _screenTitle,
    showDrawerMenu: false,
    drawerSelectedIndex: 6,
    scaffoldKey: _scaffoldKey,
    actions: _buildHeaderActions(),
    body: _buildBody(context),
  );

  Widget _buildBody(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoBanner(message: _loadError!, tone: InfoBannerTone.error),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: _loadSettings,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            children: [
              Text(
                _isChat
                    ? 'Choose how message notifications appear and sound.'
                    : 'Customize the text shown while live location is shared.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (!_isChat) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Testing shows a preview only; it does not start location sharing.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              _buildContentCard(context),
              if (_isChat) ...[
                const SizedBox(height: AppSpacing.md),
                _buildChatAlertCard(context),
              ],
              if (_saving || _hasUnsavedChanges || _saveError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      _saving
                          ? Icons.sync_rounded
                          : Icons.error_outline_rounded,
                      size: 16,
                      color: _saveError == null
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      _saving ? 'Saving…' : _saveError ?? 'Unsaved changes',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        _buildActions(context),
      ],
    );
  }

  Widget _buildContentCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Notification content',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: Key('$_typeKey-title-field'),
              controller: _headerController,
              maxLines: 1,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Header',
                helperText: 'Leave blank to hide the header.',
                prefixIcon: const Icon(Icons.title_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Clear header',
                  onPressed: () {
                    _headerController.clear();
                    _onDraftChanged();
                  },
                  icon: const Icon(Icons.clear_rounded),
                ),
              ),
              onChanged: (_) => _onDraftChanged(),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: Key('$_typeKey-message-field'),
              controller: _messageController,
              minLines: 1,
              maxLines: 3,
              maxLength: 240,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                labelText: 'Message',
                helperText: 'Leave blank for no message.',
                prefixIcon: const Icon(Icons.notes_rounded),
                suffixIcon: IconButton(
                  tooltip: 'Clear message',
                  onPressed: () {
                    _messageController.clear();
                    _onDraftChanged();
                  },
                  icon: const Icon(Icons.clear_rounded),
                ),
              ),
              onChanged: (_) => _onDraftChanged(),
            ),
            const SizedBox(height: AppSpacing.sm),
            _NotificationPreview(
              title: _headerController.text,
              message: _messageController.text,
            ),
            if (_isChat &&
                _headerController.text.trim().isEmpty &&
                _messageController.text.trim().isEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              const InfoBanner(
                key: Key('incoming-chat-blank-wear-warning'),
                message:
                    'Wear OS / Pixel Watch drops notifications when both '
                    'Header and Message are blank. Enter text in either field '
                    'to receive watch notifications.',
                tone: InfoBannerTone.warning,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildChatAlertCard(BuildContext context) {
    final preferences = _chatAlertPreferences;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              child: Text(
                'Alert behavior',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            RadioGroup<NotificationAlertSource>(
              groupValue: preferences.source,
              onChanged: (source) {
                if (source != null) {
                  _stageChatAlertPreferences(
                    preferences.copyWith(source: source),
                  );
                }
              },
              child: Column(
                children: const [
                  RadioListTile<NotificationAlertSource>(
                    title: Text('Follow system'),
                    subtitle: Text(
                      'Use Android notification sound, vibration, and flash settings.',
                    ),
                    value: NotificationAlertSource.system,
                  ),
                  RadioListTile<NotificationAlertSource>(
                    title: Text('Use app settings'),
                    subtitle: Text('Choose alert outputs below.'),
                    value: NotificationAlertSource.custom,
                  ),
                ],
              ),
            ),
            if (preferences.source == NotificationAlertSource.system) ...[
              ListTile(
                leading: const Icon(Icons.music_note_rounded),
                title: const Text('System notification sound'),
                subtitle: Text(
                  '${_systemNotificationSoundTitle ?? 'Phone default notification sound'} · '
                  'Tap to change sound and vibration',
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
                      : '${_systemFlashEnabled ? 'On' : 'Off'} in Android settings',
                ),
                trailing: const Icon(Icons.open_in_new_rounded),
                onTap: _openSystemFlashSettings,
              ),
            ],
            if (preferences.source == NotificationAlertSource.custom) ...[
              SwitchListTile(
                title: const Text('Notification sound'),
                value: preferences.ringSoundEnabled,
                onChanged: (enabled) => _stageChatAlertPreferences(
                  preferences.copyWith(ringSoundEnabled: enabled),
                ),
              ),
              if (preferences.ringSoundEnabled)
                ListTile(
                  leading: const Icon(Icons.music_note_rounded),
                  title: const Text('Choose notification sound'),
                  subtitle: Text(
                    _chatNotificationSoundTitle ??
                        (preferences.notificationSoundUri == null
                            ? 'Phone default notification sound'
                            : 'Selected notification sound'),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _chooseChatRingtone,
                ),
              SwitchListTile(
                title: const Text('Vibrate'),
                value: preferences.vibrationEnabled,
                onChanged: (enabled) => _stageChatAlertPreferences(
                  preferences.copyWith(vibrationEnabled: enabled),
                ),
              ),
              if (preferences.vibrationEnabled)
                ListTile(
                  title: const Text('Vibration pattern'),
                  trailing: DropdownButton<IncomingChatVibrationPattern>(
                    key: const Key('incoming-chat-vibration-pattern'),
                    value: preferences.vibrationPattern,
                    onChanged: (pattern) {
                      if (pattern != null) {
                        _stageChatAlertPreferences(
                          preferences.copyWith(vibrationPattern: pattern),
                        );
                      }
                    },
                    items: const [
                      DropdownMenuItem(
                        value: IncomingChatVibrationPattern.standard,
                        child: Text('Standard'),
                      ),
                      DropdownMenuItem(
                        value: IncomingChatVibrationPattern.shortPulses,
                        child: Text('Short pulses'),
                      ),
                      DropdownMenuItem(
                        value: IncomingChatVibrationPattern.longPulses,
                        child: Text('Long pulses'),
                      ),
                    ],
                  ),
                ),
              SwitchListTile(
                title: const Text('Flashlight blink'),
                subtitle: Text(
                  !_hasFlashlight
                      ? 'Requires camera permission and flashlight hardware.'
                      : preferences.flashlightEnabled
                      ? 'Android may restrict background flashlight alerts.'
                      : 'Off by default.',
                ),
                value: preferences.flashlightEnabled,
                onChanged: _setChatFlashlight,
              ),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Text(
                'Smartwatch note: in the Pixel Watch / Wear OS app, enable '
                'notifications for "Calculator". Watch alerts are muted while '
                'your phone screen is unlocked unless you disable "Mute '
                'notifications when using phone".',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final testLabel = _isChat ? 'Test message' : 'Test background notification';
    return SafeArea(
      top: false,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: Key('test-$_typeKey-notification-button'),
                  onPressed: _testing || _saving
                      ? null
                      : () => unawaited(_testNotification()),
                  icon: _testing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.notifications_active_outlined),
                  label: Text(testLabel),
                ),
              ),
              if (_isChat) ...[
                const SizedBox(width: AppSpacing.sm),
                OutlinedButton.icon(
                  key: Key('test-$_typeKey-delayed-notification-button'),
                  onPressed: _testing || _saving
                      ? null
                      : () => unawaited(
                          _testNotification(delay: const Duration(seconds: 5)),
                        ),
                  icon: const Icon(Icons.timer_outlined),
                  label: const Text('In 5s'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationPreview extends StatelessWidget {
  const _NotificationPreview({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.notifications_none_rounded,
            size: 20,
            color: colors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.trim().isEmpty ? 'No header' : title.trim(),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  message.trim().isEmpty ? 'No message' : message.trim(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
