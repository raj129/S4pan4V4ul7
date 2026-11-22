import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../application/media/chat_media_loader.dart';
import '../../application/media/chat_media_manager_service.dart';
import '../../application/services/profile_service.dart';
import 'package:photo_vault/core/app/external_activity_guard.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/entities/profile_avatar.dart';
import 'package:photo_vault/core/widgets/main_scaffold_scope.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'chat_media_manager_screen.dart';
import '../widgets/message_bubble.dart' show showReactionPicker;
import '../widgets/user_avatar.dart';

/// View and edit the name and picture other people see in chat.
///
/// Name editing opens a dialog (matching [showDataSmsNumberDialog]), while
/// tapping the avatar opens a simple picker sheet and saves immediately.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.me,
    required this.service,
    this.mediaLoader,
    this.mediaManagerService,
  });

  final ChatUser me;
  final ProfileService service;
  final ChatMediaLoader? mediaLoader;
  final ChatMediaManagerService? mediaManagerService;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late String _savedName;
  late ProfileAvatar _savedAvatar;
  Uint8List? _pendingPhoto;
  bool _savingAvatar = false;

  ProfileService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _savedName = _service.profile?.displayName ?? widget.me.displayName;
    _savedAvatar = _service.profile?.avatar ?? widget.me.avatar;
  }

  Future<void> _openMediaManager() async {
    final loader = widget.mediaLoader;
    final manager = widget.mediaManagerService;
    if (loader == null || manager == null) return;
    await openChatMediaManager(
      context,
      service: manager,
      mediaLoader: loader,
      currentUid: widget.me.uid,
    );
  }

  Future<void> _pickAvatar() async {
    if (_savingAvatar) return;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _AvatarPickerSheet(),
    );
    if (choice == null || !mounted) return;

    ProfileAvatar nextAvatar = _savedAvatar;
    Uint8List? photoBytes;
    if (choice is ProfileAvatar) {
      nextAvatar = choice;
    } else if (choice is ImageSource) {
      try {
        final file = await ExternalActivityGuard.run(
          () => ImagePicker().pickImage(
            source: choice,
            maxWidth: 512,
            maxHeight: 512,
            imageQuality: 85,
          ),
        );
        if (file == null || !mounted) return;
        photoBytes = await file.readAsBytes();
      } catch (_) {
        _snack('Could not open that image.');
        return;
      }
    } else {
      return;
    }

    setState(() {
      _savingAvatar = true;
      if (photoBytes != null) {
        _pendingPhoto = photoBytes;
      } else {
        _savedAvatar = nextAvatar;
        _pendingPhoto = null;
      }
    });

    try {
      await _service.saveProfile(
        me: widget.me,
        displayName: _savedName,
        avatar: nextAvatar,
        photoBytes: photoBytes,
      );
      if (!mounted) return;
      final saved = _service.profile;
      setState(() {
        _savedAvatar = saved?.avatar ?? nextAvatar;
        _pendingPhoto = null;
        _savingAvatar = false;
      });
      _snack('Profile picture updated.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _savedAvatar = _service.profile?.avatar ?? widget.me.avatar;
        _pendingPhoto = null;
        _savingAvatar = false;
      });
      _snack('Could not update picture: $error');
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _editNameDialog() async {
    if (_savingAvatar) return;
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => _EditNameDialog(
        currentName: _savedName,
        onSave: (nextName) async {
          await _service.saveProfile(
            me: widget.me,
            displayName: nextName,
            avatar: _savedAvatar,
          );
          return _service.profile?.displayName ?? nextName;
        },
      ),
    );
    if (saved == null || !mounted) return;
    setState(() => _savedName = saved);
    _snack('Name saved.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final canManageMedia =
        widget.mediaLoader != null && widget.mediaManagerService != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: const [QuickLockActionButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xxl,
        ),
        children: [
          Center(child: _buildAvatar(theme, _savedName)),
          const SizedBox(height: AppSpacing.md),
          Text(
            _savedName,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            widget.me.email,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
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
                ListTile(
                  leading: CircleAvatar(
                    radius: 20,
                    backgroundColor: colors.tertiaryContainer,
                    child: Icon(
                      Icons.person_outline_rounded,
                      color: colors.onTertiaryContainer,
                      size: 20,
                    ),
                  ),
                  title: Text(_savedName, style: theme.textTheme.titleSmall),
                  subtitle: const Text('Display name'),
                  trailing: const Icon(Icons.edit_outlined, size: 20),
                  onTap: _editNameDialog,
                ),
                if (canManageMedia) ...[
                  Divider(
                    height: 1,
                    indent: 56,
                    endIndent: 16,
                    color: colors.outlineVariant.withValues(alpha: 0.3),
                  ),
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
                    title: const Text('Manage chat media'),
                    subtitle: const Text(
                      'Sort attachments and clear locally cached media.',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _openMediaManager,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme, String shownName) {
    final avatar = _pendingPhoto != null
        ? CircleAvatar(radius: 56, backgroundImage: MemoryImage(_pendingPhoto!))
        : UserAvatar(avatar: _savedAvatar, name: shownName, radius: 56);

    return InkWell(
      customBorder: const CircleBorder(),
      onTap: _savingAvatar ? null : _pickAvatar,
      child: Stack(
        children: [
          avatar,
          if (_savingAvatar)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            )
          else
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: theme.colorScheme.primary,
                shape: const CircleBorder(),
                child: SizedBox.square(
                  dimension: 34,
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: 18,
                    color: theme.colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({required this.currentName, required this.onSave});

  final String currentName;
  final Future<String> Function(String nextName) onSave;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final _controller = TextEditingController(text: widget.currentName);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      setState(() => _error = 'Enter a display name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(trimmed);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Could not save your name: $error';
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
        icon: const Icon(Icons.person_outline_rounded),
        title: const Text('Display name'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choose the name other people see in chat.',
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
                  labelText: 'Display name',
                  hintText: 'Your name',
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
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _saving ? null : _save,
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

/// Simple single-sheet avatar picker: Photo (Camera/Gallery), Emoji, or
/// Initials/Color presets.
class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Text(
                'Profile picture',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: _QuickAvatarAction(
                    icon: Icons.photo_camera_rounded,
                    label: 'Camera',
                    color: cs.primary,
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _QuickAvatarAction(
                    icon: Icons.photo_library_rounded,
                    label: 'Gallery',
                    color: cs.secondary,
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _QuickAvatarAction(
                    icon: Icons.emoji_emotions_outlined,
                    label: 'Emoji',
                    color: cs.tertiary,
                    onTap: () async {
                      final emoji = await showReactionPicker(context);
                      if (emoji != null && context.mounted) {
                        Navigator.pop(context, ProfileAvatar.emoji(emoji));
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Colors & initials',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.md,
              children: [
                InkResponse(
                  radius: 28,
                  onTap: () =>
                      Navigator.pop(context, const ProfileAvatar.initials()),
                  child: const UserAvatar(
                    avatar: ProfileAvatar.initials(),
                    name: 'Aa',
                    radius: 24,
                  ),
                ),
                for (var i = 0; i < avatarPresetColors.length; i++)
                  InkResponse(
                    radius: 28,
                    onTap: () =>
                        Navigator.pop(context, ProfileAvatar.preset(i)),
                    child: UserAvatar(
                      avatar: ProfileAvatar.preset(i),
                      name: '',
                      radius: 24,
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

class _QuickAvatarAction extends StatelessWidget {
  const _QuickAvatarAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
