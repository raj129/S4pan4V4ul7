import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/media/chat_media_loader.dart';
import '../../application/media/chat_media_manager_service.dart';
import '../../application/services/profile_service.dart';
import '../../application/services/data_sms_service.dart';
import '../../../calls/data/phone_contact_source.dart';
import '../../domain/entities/chat_user.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../screens/chat_media_manager_screen.dart';
import 'user_avatar.dart';
import 'data_sms_number_dialog.dart';

/// Contact details and a private, local-only nickname editor.
Future<void> showContactInfoSheet(
  BuildContext context, {
  required ProfileService profileService,
  required ChatUser user,
  ChatMediaLoader? mediaLoader,
  ChatMediaManagerService? mediaManagerService,
  String? threadId,
  DataSmsService? dataSms,
  ValueChanged<String?>? onSmsNumberChanged,
  PhoneContactSource contacts = const PlatformPhoneContactSource(),
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ContactInfoSheet(
      service: profileService,
      user: user,
      messenger: messenger,
      mediaLoader: mediaLoader,
      mediaManagerService: mediaManagerService,
      threadId: threadId,
      dataSms: dataSms,
      onSmsNumberChanged: onSmsNumberChanged,
      contacts: contacts,
    ),
  );
}

class _ContactInfoSheet extends StatefulWidget {
  const _ContactInfoSheet({
    required this.service,
    required this.user,
    required this.messenger,
    required this.mediaLoader,
    required this.mediaManagerService,
    required this.threadId,
    required this.dataSms,
    required this.onSmsNumberChanged,
    required this.contacts,
  });

  final ProfileService service;
  final ChatUser user;
  final ScaffoldMessengerState? messenger;
  final ChatMediaLoader? mediaLoader;
  final ChatMediaManagerService? mediaManagerService;
  final String? threadId;
  final DataSmsService? dataSms;
  final ValueChanged<String?>? onSmsNumberChanged;
  final PhoneContactSource contacts;

  @override
  State<_ContactInfoSheet> createState() => _ContactInfoSheetState();
}

class _ContactInfoSheetState extends State<_ContactInfoSheet> {
  late String? _savedAlias;
  String? _smsNumber;
  String? _smsError;
  bool _smsLoading = false;
  bool _smsEditing = false;

  @override
  void initState() {
    super.initState();
    _savedAlias = widget.service.aliasFor(widget.user.uid);
    if (widget.dataSms != null && widget.threadId != null) {
      unawaited(_loadSmsNumber());
    }
  }

  Future<void> _loadSmsNumber() async {
    setState(() {
      _smsLoading = true;
      _smsError = null;
    });
    try {
      final number = await widget.dataSms!.phone(widget.threadId!);
      if (mounted) setState(() => _smsNumber = number);
    } catch (error) {
      if (mounted) {
        setState(() => _smsError = 'Could not load Data SMS number: $error');
      }
    } finally {
      if (mounted) setState(() => _smsLoading = false);
    }
  }

  Future<void> _editSmsNumber() async {
    if (_smsLoading || _smsEditing) return;
    setState(() => _smsEditing = true);
    try {
      await showDataSmsNumberDialog(
        context,
        currentNumber: _smsNumber,
        contacts: widget.contacts,
        saveNumber: (number) async {
          await widget.dataSms!.setPhone(widget.threadId!, number);
          widget.onSmsNumberChanged?.call(number);
          if (mounted) setState(() => _smsNumber = number);
        },
      );
    } finally {
      if (mounted) setState(() => _smsEditing = false);
    }
  }

  String? _normalizedAlias(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == widget.user.displayName
        ? null
        : trimmed;
  }

  Future<void> _editNicknameDialog() async {
    final result = await showDialog<({String? alias})>(
      context: context,
      builder: (_) => _EditNicknameDialog(
        realName: widget.user.displayName,
        currentAlias: _savedAlias,
        onSave: (raw) async {
          final next = _normalizedAlias(raw);
          await widget.service.setAlias(widget.user.uid, next);
          return next;
        },
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _savedAlias = result.alias);
    _showSnack(result.alias == null ? 'Nickname removed.' : 'Nickname saved.');
  }

  Future<void> _openMediaManager() async {
    final loader = widget.mediaLoader;
    final manager = widget.mediaManagerService;
    final threadId = widget.threadId;
    if (loader == null || manager == null || threadId == null) return;
    await openChatMediaManager(
      context,
      service: manager,
      mediaLoader: loader,
      currentUid: loader.accountId,
      threadId: threadId,
      title: 'Media in this chat',
    );
  }

  void _showSnack(String message) {
    widget.messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _viewAvatar(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              elevation: 8,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              color: Theme.of(dialogContext).colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: UserAvatar(
                  avatar: widget.user.avatar,
                  name: _savedAlias ?? widget.user.displayName,
                  radius: 110,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(dialogContext).pop(),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = widget.user;
    final shownName = _savedAlias ?? user.displayName;
    final canManageMedia =
        widget.mediaLoader != null &&
        widget.mediaManagerService != null &&
        widget.threadId != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.md,
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => _viewAvatar(context),
                      borderRadius: BorderRadius.circular(52),
                      child: Tooltip(
                        message: 'View profile picture',
                        child: UserAvatar(
                          avatar: user.avatar,
                          name: shownName,
                          radius: 48,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      shownName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (_savedAlias != null) ...[
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        user.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Card(
                elevation: 0,
                color: colors.surfaceContainerLow,
                margin: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Column(
                  children: [
                    if (widget.dataSms != null && widget.threadId != null) ...[
                      ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: colors.secondaryContainer,
                          child: Icon(
                            Icons.sim_card_outlined,
                            color: colors.onSecondaryContainer,
                            size: 20,
                          ),
                        ),
                        title: const Text('Data SMS number'),
                        subtitle: Text(
                          _smsLoading
                              ? 'Loading...'
                              : _smsError ??
                                    (_smsNumber == null
                                        ? 'Add recipient mobile number'
                                        : '$_smsNumber\nUnverified, saved only on this device'),
                        ),
                        trailing: Icon(
                          _smsError != null
                              ? Icons.refresh
                              : Icons.edit_outlined,
                          size: 20,
                        ),
                        onTap: _smsLoading || _smsEditing
                            ? null
                            : _smsError != null
                            ? _loadSmsNumber
                            : _editSmsNumber,
                      ),
                      if (canManageMedia)
                        Divider(
                          height: 1,
                          indent: 56,
                          endIndent: 16,
                          color: colors.outlineVariant.withValues(alpha: 0.3),
                        ),
                    ],
                    if (canManageMedia) ...[
                      ListTile(
                        leading: CircleAvatar(
                          radius: 20,
                          backgroundColor: colors.primaryContainer,
                          child: Icon(
                            Icons.perm_media_outlined,
                            color: colors.onPrimaryContainer,
                            size: 20,
                          ),
                        ),
                        title: const Text('Media in this chat'),
                        subtitle: const Text(
                          'Browse by category, sort by size, and clear cached files.',
                        ),
                        trailing: const Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                        ),
                        onTap: _openMediaManager,
                      ),
                      Divider(
                        height: 1,
                        indent: 56,
                        endIndent: 16,
                        color: colors.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ],
                    ListTile(
                      leading: CircleAvatar(
                        radius: 20,
                        backgroundColor: colors.tertiaryContainer,
                        child: Icon(
                          Icons.badge_outlined,
                          color: colors.onTertiaryContainer,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        _savedAlias ?? 'No nickname',
                        style: theme.textTheme.titleSmall,
                      ),
                      subtitle: const Text('Nickname visible only to you'),
                      trailing: const Icon(Icons.edit_outlined, size: 20),
                      onTap: _editNicknameDialog,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
  }
}

class _EditNicknameDialog extends StatefulWidget {
  const _EditNicknameDialog({
    required this.realName,
    required this.currentAlias,
    required this.onSave,
  });

  final String realName;
  final String? currentAlias;
  final Future<String?> Function(String raw) onSave;

  @override
  State<_EditNicknameDialog> createState() => _EditNicknameDialogState();
}

class _EditNicknameDialogState extends State<_EditNicknameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.currentAlias ?? '',
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save({bool clear = false}) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(clear ? '' : _controller.text);
      if (mounted) Navigator.of(context).pop((alias: saved));
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not save nickname: $error';
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        icon: const Icon(Icons.badge_outlined),
        title: const Text('Nickname'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Visible only to you on this device.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                enabled: !_saving,
                autofocus: true,
                maxLength: ProfileService.maxNameLength,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _save(),
                decoration: InputDecoration(
                  labelText: 'Nickname',
                  hintText: widget.realName,
                  errorText: _error,
                  suffixIcon: ListenableBuilder(
                    listenable: _controller,
                    builder: (_, _) => _controller.text.isEmpty || _saving
                        ? const SizedBox.shrink()
                        : IconButton(
                            tooltip: 'Clear',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: _controller.clear,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.currentAlias != null)
            TextButton(
              onPressed: _saving ? null : () => _save(clear: true),
              child: const Text('Use real name'),
            ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : () => _save(),
            child: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
