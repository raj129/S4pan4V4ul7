import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/media/chat_media_loader.dart';
import '../../application/media/chat_media_manager_service.dart';
import '../../application/services/profile_service.dart';
import '../../domain/entities/chat_user.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../screens/chat_media_manager_screen.dart';
import 'user_avatar.dart';

/// Contact details and a private, local-only nickname editor.
Future<void> showContactInfoSheet(
  BuildContext context, {
  required ProfileService profileService,
  required ChatUser user,
  ChatMediaLoader? mediaLoader,
  ChatMediaManagerService? mediaManagerService,
  String? threadId,
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
  });

  final ProfileService service;
  final ChatUser user;
  final ScaffoldMessengerState? messenger;
  final ChatMediaLoader? mediaLoader;
  final ChatMediaManagerService? mediaManagerService;
  final String? threadId;

  @override
  State<_ContactInfoSheet> createState() => _ContactInfoSheetState();
}

class _ContactInfoSheetState extends State<_ContactInfoSheet> {
  late final TextEditingController _controller;
  late String? _savedAlias;
  bool _editing = false;
  bool _saving = false;
  bool _suppressControllerListener = false;

  @override
  void initState() {
    super.initState();
    _savedAlias = widget.service.aliasFor(widget.user.uid);
    _controller = TextEditingController(text: _savedAlias ?? '')
      ..addListener(_onControllerChanged);
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
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colors.primary.withValues(alpha: 0.35),
                            width: 2,
                          ),
                        ),
                        child: UserAvatar(
                          avatar: user.avatar,
                          name: shownName,
                          radius: 44,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        shownName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      if (_savedAlias != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          user.displayName,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        user.email,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (canManageMedia) ...[
                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.perm_media_outlined,
                      color: colors.primary,
                    ),
                    title: const Text('Media in this chat'),
                    subtitle: const Text(
                      'Browse by category, sort by size, and clear cached files.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openMediaManager,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (_editing) ...[
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
                    suffixIcon: ListenableBuilder(
                      listenable: _controller,
                      builder: (_, _) => _controller.text.isEmpty
                          ? const SizedBox.shrink()
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _saving ? null : _controller.clear,
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
                      child: OutlinedButton(
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
              ] else ...[
                Card(
                  child: ListTile(
                    leading: Icon(Icons.badge_outlined, color: colors.primary),
                    title: Text(
                      _savedAlias ?? 'No nickname',
                      style: theme.textTheme.titleSmall,
                    ),
                    subtitle: const Text('Nickname visible only to you'),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
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
