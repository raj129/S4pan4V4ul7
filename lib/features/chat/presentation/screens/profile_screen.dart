import 'dart:async';
import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../application/media/chat_media_loader.dart';
import '../../application/media/chat_media_manager_service.dart';
import '../../application/services/profile_service.dart';
import 'package:photo_vault/core/app/external_activity_guard.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/entities/profile_avatar.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import 'chat_media_manager_screen.dart';
import '../widgets/user_avatar.dart';

/// Edit the name and picture other people see in chat.
///
/// Changes are staged in an explicit edit mode until Save is pressed.
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
  late final TextEditingController _name;
  late String _initialName;
  late ProfileAvatar _initialAvatar;
  late ProfileAvatar _avatar;

  /// A newly picked photo, shown from memory until it is uploaded on Save.
  Uint8List? _pickedPhoto;
  bool _editing = false;
  bool _saving = false;
  bool _suppressNameListener = false;

  ProfileService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _initialName = _service.profile?.displayName ?? widget.me.displayName;
    _initialAvatar = _service.profile?.avatar ?? widget.me.avatar;
    _avatar = _initialAvatar;
    _name = TextEditingController(text: _initialName)
      ..addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _dirty =>
      _pickedPhoto != null ||
      _avatar != _initialAvatar ||
      _name.text.trim() != _initialName;

  bool get _valid => _name.text.trim().isNotEmpty;

  void _onNameChanged() {
    if (mounted && !_suppressNameListener) setState(() {});
  }

  void _setName(String value) {
    _suppressNameListener = true;
    _name.text = value;
    _suppressNameListener = false;
  }

  void _startEditing() {
    _setName(_initialName);
    setState(() {
      _avatar = _initialAvatar;
      _pickedPhoto = null;
      _editing = true;
    });
  }

  void _cancelEditing() {
    _setName(_initialName);
    setState(() {
      _avatar = _initialAvatar;
      _pickedPhoto = null;
      _editing = false;
    });
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
    final choice = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AvatarPickerSheet(),
    );
    if (choice == null || !mounted) return;
    if (choice is ProfileAvatar) {
      setState(() {
        _avatar = choice;
        _pickedPhoto = null;
      });
    } else if (choice is ImageSource) {
      try {
        // Downsized at the source so a 12 MP photo is never held in memory.
        final file = await ExternalActivityGuard.run(
          () => ImagePicker().pickImage(
            source: choice,
            maxWidth: 512,
            maxHeight: 512,
            imageQuality: 85,
          ),
        );
        if (file == null) return;
        final bytes = await file.readAsBytes();
        if (!mounted) return;
        setState(() => _pickedPhoto = bytes);
      } catch (_) {
        _snack('Could not open that image.');
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (!_editing || _saving || !_dirty || !_valid) return;
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await _service.saveProfile(
        me: widget.me,
        displayName: _name.text.trim(),
        avatar: _avatar,
        photoBytes: _pickedPhoto,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not save your profile: $error');
      return;
    }
    if (!mounted) return;
    final saved = _service.profile;
    final name = saved?.displayName ?? _name.text.trim();
    final avatar = saved?.avatar ?? _avatar;
    _setName(name);
    setState(() {
      _initialName = name;
      _initialAvatar = avatar;
      _avatar = avatar;
      _pickedPhoto = null;
      _editing = false;
      _saving = false;
    });
    _snack('Profile saved.');
  }

  Future<void> _handleBack() async {
    if (_saving || !_editing || !_dirty) return;
    final discard = await _confirmDiscard();
    if (discard != true || !mounted) return;
    _cancelEditing();
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      final router = GoRouter.of(context);
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/chat');
      }
    }
  }

  Future<bool> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your profile changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final shownName = _name.text.trim().isEmpty
        ? _initialName
        : _name.text.trim();
    final canManageMedia =
        widget.mediaLoader != null && widget.mediaManagerService != null;
    return PopScope(
      canPop: !_saving && (!_editing || !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_editing ? 'Edit profile' : 'Profile')),
        bottomNavigationBar: _editing
            ? SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: Border(
                      top: BorderSide(color: colors.outlineVariant),
                    ),
                  ),
                  child: Row(
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
                          onPressed: _saving || !_dirty || !_valid
                              ? null
                              : _save,
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
                ),
              )
            : null,
        body: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            Card(
              color: colors.surfaceContainerLow,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _editing ? 'EDITING YOUR PROFILE' : 'YOUR CHAT PROFILE',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _buildAvatar(theme, shownName),
                    if (_editing) ...[
                      const SizedBox(height: AppSpacing.sm),
                      TextButton.icon(
                        onPressed: _saving ? null : _pickAvatar,
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: const Text('Change picture'),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      shownName,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.alternate_email_rounded,
                            size: 15,
                            color: colors.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            widget.me.email,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!_editing) ...[
                      const SizedBox(height: AppSpacing.lg),
                      FilledButton.tonalIcon(
                        onPressed: _startEditing,
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Edit profile'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (canManageMedia) ...[
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: ListTile(
                  leading: Icon(
                    Icons.perm_media_outlined,
                    color: colors.primary,
                  ),
                  title: const Text('Manage chat media'),
                  subtitle: const Text(
                    'Sort attachments and clear locally cached media.',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: _openMediaManager,
                ),
              ),
            ],
            if (_editing) ...[
              const SizedBox(height: AppSpacing.lg),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Profile details',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _name,
                        enabled: !_saving,
                        maxLength: ProfileService.maxNameLength,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          prefixIcon: Icon(Icons.person_outline_rounded),
                          helperText: 'Shown to people you chat with.',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme, String shownName) {
    final avatar = _pickedPhoto != null
        ? CircleAvatar(radius: 56, backgroundImage: MemoryImage(_pickedPhoto!))
        : UserAvatar(avatar: _avatar, name: shownName, radius: 56);
    final framedAvatar = Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.35),
          width: 2.5,
        ),
      ),
      child: avatar,
    );

    if (!_editing) return framedAvatar;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: _saving ? null : _pickAvatar,
      child: Stack(
        children: [
          framedAvatar,
          Positioned(
            right: 4,
            bottom: 4,
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

/// Pops a [ProfileAvatar] (default / emoji / initials) or an [ImageSource]
/// (photo to pick).
class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.70;
    return SizedBox(
      height: height,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: theme.colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                tabs: const [
                  Tab(
                    icon: Icon(Icons.palette_outlined, size: 20),
                    text: 'Default',
                  ),
                  Tab(
                    icon: Icon(Icons.emoji_emotions_outlined, size: 20),
                    text: 'Emoji',
                  ),
                  Tab(
                    icon: Icon(Icons.photo_camera_outlined, size: 20),
                    text: 'Photo',
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Expanded(
              child: TabBarView(
                children: [
                  GridView.count(
                    crossAxisCount: 4,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    children: [
                      Material(
                        color: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: theme.colorScheme.outlineVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => Navigator.pop(
                            context,
                            const ProfileAvatar.initials(),
                          ),
                          child: Center(
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant,
                                  width: 1.5,
                                ),
                              ),
                              child: const UserAvatar(
                                avatar: ProfileAvatar.initials(),
                                name: 'Aa',
                                radius: 26,
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (var i = 0; i < avatarPresetColors.length; i++)
                        Material(
                          color: theme.colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () =>
                                Navigator.pop(context, ProfileAvatar.preset(i)),
                            child: Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          avatarPresetColors[i %
                                                  avatarPresetColors.length]
                                              .withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: UserAvatar(
                                  avatar: ProfileAvatar.preset(i),
                                  name: '',
                                  radius: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  EmojiPicker(
                    onEmojiSelected: (_, emoji) => Navigator.pop(
                      context,
                      ProfileAvatar.emoji(emoji.emoji),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _PhotoSourceCard(
                          icon: Icons.photo_library_rounded,
                          color: theme.colorScheme.primary,
                          title: 'Choose from gallery',
                          subtitle: 'Select an existing image from your device',
                          onTap: () =>
                              Navigator.pop(context, ImageSource.gallery),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _PhotoSourceCard(
                          icon: Icons.photo_camera_rounded,
                          color: theme.colorScheme.secondary,
                          title: 'Take a photo',
                          subtitle: 'Use your camera to take a new picture',
                          onTap: () =>
                              Navigator.pop(context, ImageSource.camera),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoSourceCard extends StatelessWidget {
  const _PhotoSourceCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
