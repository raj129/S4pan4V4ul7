import 'dart:async';

import 'package:flutter/material.dart';

import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/core/widgets/base_screen_shell.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({
    required this.settingsRepository,
    this.onTestNotification,
    this.onNotificationSettingsChanged,
    super.key,
  });

  final SettingsRepository settingsRepository;
  final Future<void> Function()? onTestNotification;
  final Future<void> Function()? onNotificationSettingsChanged;

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final _incomingChatTitleController = TextEditingController();
  final _incomingChatMessageController = TextEditingController();
  final _backgroundLocationTitleController = TextEditingController();
  final _backgroundLocationMessageController = TextEditingController();
  Timer? _saveTimer;
  Future<void> _saveTail = Future<void>.value();
  int _revision = 0;
  bool _loading = true;
  bool _saving = false;
  bool _testingNotification = false;
  bool _refreshLocationNotificationAfterSave = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final values = await Future.wait([
        widget.settingsRepository.getIncomingChatAlertTitle(),
        widget.settingsRepository.getIncomingChatAlertText(),
        widget.settingsRepository.getBackgroundLocationAlertTitle(),
        widget.settingsRepository.getBackgroundLocationAlertText(),
      ]);
      if (!mounted) return;
      setState(() {
        _incomingChatTitleController.text = values[0];
        _incomingChatMessageController.text = values[1];
        _backgroundLocationTitleController.text = values[2];
        _backgroundLocationMessageController.text = values[3];
        _loading = false;
      });
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
    final pendingSave = _saveTimer;
    pendingSave?.cancel();
    if (pendingSave != null) {
      unawaited(_flushPendingSave());
    }
    _incomingChatTitleController.dispose();
    _incomingChatMessageController.dispose();
    _backgroundLocationTitleController.dispose();
    _backgroundLocationMessageController.dispose();
    super.dispose();
  }

  Future<void> _flushPendingSave() async {
    try {
      await _enqueueSave();
      if (_refreshLocationNotificationAfterSave) {
        await widget.onNotificationSettingsChanged?.call();
      }
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'notification settings persistence',
        ),
      );
    }
  }

  void _scheduleSave({bool refreshLocationNotification = false}) {
    _saveTimer?.cancel();
    _refreshLocationNotificationAfterSave |= refreshLocationNotification;
    final revision = ++_revision;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      _saveTimer = null;
      unawaited(_saveSettings(revision).then<void>((_) {}));
    });
  }

  Future<bool> _saveSettings([int? revision]) async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final saveRevision = revision ?? ++_revision;
    final refreshLocationNotification = _refreshLocationNotificationAfterSave;
    try {
      await _enqueueSave();
      if (mounted && saveRevision == _revision) {
        setState(() {
          _saving = false;
          _saveError = null;
        });
      }
      if (refreshLocationNotification && saveRevision == _revision) {
        _refreshLocationNotificationAfterSave = false;
        try {
          await widget.onNotificationSettingsChanged?.call();
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Could not update the background location notification: '
                  '$error',
                ),
              ),
            );
          }
        }
      }
      return true;
    } catch (error) {
      if (mounted && saveRevision == _revision) {
        setState(() {
          _saving = false;
          _saveError = 'Could not save automatically.';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save notification settings: $error'),
          ),
        );
      }
      return false;
    }
  }

  Future<void> _enqueueSave() {
    final repository = widget.settingsRepository;
    final incomingChatTitle = _incomingChatTitleController.text.trim();
    final incomingChatMessage = _incomingChatMessageController.text.trim();
    final locationTitle = _backgroundLocationTitleController.text.trim();
    final locationMessage = _backgroundLocationMessageController.text.trim();
    final operation = _saveTail.then((_) async {
      await repository.setIncomingChatAlertTitle(incomingChatTitle);
      await repository.setIncomingChatAlertText(incomingChatMessage);
      await repository.setBackgroundLocationAlertTitle(locationTitle);
      await repository.setBackgroundLocationAlertText(locationMessage);
    });
    _saveTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  Future<void> _testIncomingChatNotification() async {
    final testNotification = widget.onTestNotification;
    if (testNotification == null || _testingNotification) return;
    setState(() => _testingNotification = true);
    try {
      if (!await _saveSettings()) return;
      await testNotification();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Test notification sent.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send test notification: $error')),
      );
    } finally {
      if (mounted) setState(() => _testingNotification = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BaseScreenShell(
      title: 'Notifications',
      showDrawerMenu: false,
      drawerSelectedIndex: 6,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_loadError != null) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          InfoBanner(message: _loadError!, tone: InfoBannerTone.error),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: _loadSettings,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.xl),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Text(
            'Personalize the headers and messages shown for each notification. '
            'Leave a header empty to hide it.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _NotificationEditorCard(
          key: const Key('incoming-chat-notification-card'),
          keyPrefix: 'incoming-chat-alert',
          title: 'Incoming chat',
          description: 'Alerts when a new chat message arrives.',
          icon: Icons.chat_bubble_outline_rounded,
          headerController: _incomingChatTitleController,
          messageController: _incomingChatMessageController,
          headerHint: 'Leave blank to hide the header',
          messageHint: 'Leave blank for no message',
          saving: _saving,
          saveError: _saveError,
          onChanged: _scheduleSave,
        ),
        const SizedBox(height: AppSpacing.md),
        _NotificationEditorCard(
          key: const Key('background-location-notification-card'),
          keyPrefix: 'background-location-alert',
          title: 'Background location',
          description: 'Shown while live location is shared in the background.',
          icon: Icons.location_on_outlined,
          headerController: _backgroundLocationTitleController,
          messageController: _backgroundLocationMessageController,
          headerHint: 'Leave blank to hide the header',
          messageHint: SettingsRepository.defaultBackgroundLocationAlertText,
          saving: _saving,
          saveError: _saveError,
          onChanged: () => _scheduleSave(refreshLocationNotification: true),
        ),
        if (widget.onTestNotification != null) ...[
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                key: const Key('test-incoming-chat-notification-button'),
                onPressed: _testingNotification
                    ? null
                    : () => unawaited(_testIncomingChatNotification()),
                icon: _testingNotification
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.notifications_active_outlined),
                label: const Text('Test chat notification'),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _NotificationEditorCard extends StatelessWidget {
  const _NotificationEditorCard({
    required this.title,
    required this.keyPrefix,
    required this.description,
    required this.icon,
    required this.headerController,
    required this.messageController,
    required this.headerHint,
    required this.messageHint,
    required this.saving,
    required this.saveError,
    required this.onChanged,
    super.key,
  });

  final String title;
  final String keyPrefix;
  final String description;
  final IconData icon;
  final TextEditingController headerController;
  final TextEditingController messageController;
  final String headerHint;
  final String messageHint;
  final bool saving;
  final String? saveError;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final borderRadius = BorderRadius.circular(16);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            color: colors.primaryContainer.withValues(alpha: 0.45),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: colors.onPrimaryContainer),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  key: Key('$keyPrefix-title-field'),
                  controller: headerController,
                  maxLines: 1,
                  textInputAction: TextInputAction.next,
                  decoration:
                      _decoration(
                        context,
                        label: 'Notification header',
                        hint: headerHint,
                        icon: Icons.title_rounded,
                        borderRadius: borderRadius,
                      ).copyWith(
                        suffixIcon: IconButton(
                          key: Key('clear-$keyPrefix-title-button'),
                          tooltip: 'Clear notification header',
                          onPressed: () {
                            headerController.clear();
                            onChanged();
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                      ),
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onChanged(),
                ),
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: Key('$keyPrefix-field'),
                  controller: messageController,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration:
                      _decoration(
                        context,
                        label: 'Notification message',
                        hint: messageHint,
                        icon: Icons.notes_rounded,
                        borderRadius: borderRadius,
                      ).copyWith(
                        suffixIcon: IconButton(
                          key: Key('clear-$keyPrefix-button'),
                          tooltip: 'Clear notification message',
                          onPressed: () {
                            messageController.clear();
                            onChanged();
                          },
                          icon: const Icon(Icons.clear_rounded),
                        ),
                      ),
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onChanged(),
                ),
                const SizedBox(height: AppSpacing.md),
                _NotificationPreview(
                  title: headerController.text,
                  message: messageController.text,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      saving
                          ? Icons.sync_rounded
                          : saveError == null
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 16,
                      color: saveError == null
                          ? colors.onSurfaceVariant
                          : colors.error,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        saving
                            ? 'Saving…'
                            : saveError ?? 'Changes save automatically',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: saveError == null
                              ? colors.onSurfaceVariant
                              : colors.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(
    BuildContext context, {
    required String label,
    required String hint,
    required IconData icon,
    required BorderRadius borderRadius,
  }) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.45),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: borderRadius,
        borderSide: BorderSide(color: colors.primary, width: 1.5),
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
