import 'package:flutter/material.dart';

import '../../application/services/profile_service.dart';
import '../../domain/entities/chat_user.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'user_avatar.dart';

/// Contact details with the private nickname editor.
///
/// Nicknames are only visible to the local user; the contact keeps their own
/// name for everyone else. Editing happens inline in the sheet, so there is no
/// second route stacked on top of it.
Future<void> showContactInfoSheet(
  BuildContext context, {
  required ProfileService profileService,
  required ChatUser user,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => _ContactInfoSheet(
      service: profileService,
      user: user,
      messenger: messenger,
    ),
  );
}

class _ContactInfoSheet extends StatefulWidget {
  const _ContactInfoSheet({
    required this.service,
    required this.user,
    required this.messenger,
  });

  final ProfileService service;
  final ChatUser user;
  final ScaffoldMessengerState? messenger;

  @override
  State<_ContactInfoSheet> createState() => _ContactInfoSheetState();
}

class _ContactInfoSheetState extends State<_ContactInfoSheet> {
  late final TextEditingController _controller;
  late final String? _initialAlias;

  @override
  void initState() {
    super.initState();
    _initialAlias = widget.service.aliasFor(widget.user.uid);
    _controller = TextEditingController(text: _initialAlias ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Closes the sheet first and only then updates the alias, so the rebuilds
  /// this triggers elsewhere never touch a route that is being removed.
  Future<void> _commit(String? alias) async {
    final trimmed = alias?.trim() ?? '';
    // A nickname equal to the real name is the same as having none.
    final next = trimmed.isEmpty || trimmed == widget.user.displayName
        ? null
        : trimmed;
    final navigator = Navigator.of(context);
    if (next == _initialAlias) {
      navigator.pop();
      return;
    }
    final service = widget.service;
    final uid = widget.user.uid;
    final messenger = widget.messenger;
    navigator.pop();
    await service.setAlias(uid, next);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(next == null ? 'Nickname removed.' : 'Nickname saved.'),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = widget.user;
    final shownName = _initialAlias ?? user.displayName;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
              elevation: 0,
              color: theme.colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(alpha: 0.35),
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
                    if (_initialAlias != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Real name: ${user.displayName}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              maxLength: ProfileService.maxNameLength,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onSubmitted: _commit,
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
                          onPressed: _controller.clear,
                        ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                if (_initialAlias != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _commit(null),
                      child: const Text('Reset'),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: _initialAlias != null ? 1 : 2,
                  child: FilledButton(
                    onPressed: () => _commit(_controller.text),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
