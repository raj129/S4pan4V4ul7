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
  late final TextEditingController _controller;
  late String? _savedAlias;
  bool _editing = false;
  bool _saving = false;
  bool _suppressControllerListener = false;
  String? _smsNumber;
  String? _smsError;
  bool _smsLoading = false;
  bool _smsEditing = false;

  @override
  void initState() {
    super.initState();
    _savedAlias = widget.service.aliasFor(widget.user.uid);
    _controller = TextEditingController(text: _savedAlias ?? '')
      ..addListener(_onControllerChanged);
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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _normalizedAlias(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty || trimmed == widget.user.displayName
        ? null
        : trimmed;
  }

  void _onControllerChanged() {
    if (mounted && !_suppressControllerListener) setState(() {});
  }

  void _setControllerText(String value) {
    _suppressControllerListener = true;
    _controller.text = value;
    _suppressControllerListener = false;
  }

  bool get _hasPendingChanges =>
      _normalizedAlias(_controller.text) != _savedAlias;

  void _startEditing() {
    _setControllerText(_savedAlias ?? '');
    setState(() {
      _editing = true;
    });
  }

  void _cancelEditing() {
    _setControllerText(_savedAlias ?? '');
    setState(() {
      _editing = false;
    });
  }

  void _useRealName() {
    _controller.clear();
  }

  Future<void> _saveAlias() async {
    if (_saving) return;
    if (!_hasPendingChanges) {
      setState(() => _editing = false);
      return;
    }
    final next = _normalizedAlias(_controller.text);
    setState(() => _saving = true);
    try {
      await widget.service.setAlias(widget.user.uid, next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showSnack('Could not save nickname: $error');
      return;
    }
    if (!mounted) return;
    _setControllerText(next ?? '');
    setState(() {
      _savedAlias = next;
      _editing = false;
      _saving = false;
    });
    _showSnack(next == null ? 'Nickname removed.' : 'Nickname saved.');
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

  Future<void> _handleBack() async {
    if (_saving || !_editing || !_hasPendingChanges) return;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard nickname changes?'),
        content: const Text('Your nickname changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard != true || !mounted) return;
    _cancelEditing();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
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

    return PopScope(
      canPop: !_saving && !(_editing && _hasPendingChanges),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
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
                      if (canManageMedia || !_editing)
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
                      if (!_editing)
                        Divider(
                          height: 1,
                          indent: 56,
                          endIndent: 16,
                          color: colors.outlineVariant.withValues(alpha: 0.3),
                        ),
                    ],
                    if (!_editing)
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
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_editing) ...[
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
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _controller,
                          enabled: !_saving,
                          maxLength: ProfileService.maxNameLength,
                          textCapitalization: TextCapitalization.words,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _saveAlias(),
                          decoration: InputDecoration(
                            labelText: 'Nickname',
                            hintText: user.displayName,
                            helperText: 'Visible only to you on this device.',
                            prefixIcon: const Icon(Icons.edit_outlined),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: AppRadius.all(AppRadius.md),
                              borderSide: BorderSide.none,
                            ),
                            suffixIcon: ListenableBuilder(
                              listenable: _controller,
                              builder: (_, _) => _controller.text.isEmpty
                                  ? const SizedBox.shrink()
                                  : IconButton(
                                      tooltip: 'Clear',
                                      icon: const Icon(Icons.close_rounded),
                                      onPressed: _saving
                                          ? null
                                          : _controller.clear,
                                    ),
                            ),
                          ),
                        ),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _saving || _controller.text.isEmpty
                                ? null
                                : _useRealName,
                            icon: const Icon(Icons.person_outline_rounded),
                            label: const Text('Use real name'),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  backgroundColor:
                                      colors.surfaceContainerHighest,
                                  foregroundColor: colors.onSurface,
                                ),
                                onPressed: _saving ? null : _cancelEditing,
                                child: const Text('Cancel'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: FilledButton(
                                onPressed: _saving ? null : _saveAlias,
                                child: _saving
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Save'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                FilledButton.tonalIcon(
                  onPressed: _startEditing,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit nickname'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
