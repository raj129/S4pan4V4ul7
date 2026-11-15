import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import '../widgets/message_bubble.dart' show ThemedEmojiPicker;
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
        appBar: AppBar(
          title: Text(_editing ? 'Edit profile' : 'Profile'),
          actions: const [QuickLockActionButton()],
        ),
        bottomNavigationBar: _editing
            ? SafeArea(
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
                        child: TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: colors.surfaceContainerHighest,
                            foregroundColor: colors.onSurface,
                          ),
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
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [
            Center(child: _buildAvatar(theme, shownName)),
            if (_editing) ...[
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: TextButton.icon(
                  onPressed: _saving ? null : _pickAvatar,
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Change picture'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              shownName,
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
            if (!_editing) ...[
              const SizedBox(height: AppSpacing.lg),
              Center(
                child: FilledButton.tonalIcon(
                  onPressed: _startEditing,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit profile'),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            if (_editing) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Display name',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(
                        controller: _name,
                        enabled: !_saving,
                        maxLength: ProfileService.maxNameLength,
                        textCapitalization: TextCapitalization.words,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _save(),
                        decoration: InputDecoration(
                          hintText: 'Your name',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          fillColor: colors.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: AppRadius.all(AppRadius.md),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (canManageMedia)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.xs,
                  ),
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
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar(ThemeData theme, String shownName) {
    final avatar = _pickedPhoto != null
        ? CircleAvatar(radius: 56, backgroundImage: MemoryImage(_pickedPhoto!))
        : UserAvatar(avatar: _avatar, name: shownName, radius: 56);

    if (!_editing) return avatar;
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: _saving ? null : _pickAvatar,
      child: Stack(
        children: [
          avatar,
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

/// Pops a [ProfileAvatar] (default / emoji / initials) or an [ImageSource]
/// (photo to pick).
class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final height = MediaQuery.sizeOf(context).height * 0.68;
    return SizedBox(
      height: height,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Text(
                'Choose avatar',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(999),
              ),
              child: TabBar(
                dividerColor: Colors.transparent,
                splashBorderRadius: BorderRadius.circular(999),
                indicator: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: cs.primaryContainer,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: cs.onPrimaryContainer,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                tabs: const [
                  Tab(height: 38, text: 'Default'),
                  Tab(height: 38, text: 'Emoji'),
                  Tab(height: 38, text: 'Photo'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: TabBarView(
                children: [
                  GridView.count(
                    crossAxisCount: 4,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    mainAxisSpacing: AppSpacing.lg,
                    crossAxisSpacing: AppSpacing.lg,
                    children: [
                      Center(
                        child: InkResponse(
                          radius: 34,
                          onTap: () => Navigator.pop(
                            context,
                            const ProfileAvatar.initials(),
                          ),
                          child: const UserAvatar(
                            avatar: ProfileAvatar.initials(),
                            name: 'Aa',
                            radius: 30,
                          ),
                        ),
                      ),
                      for (var i = 0; i < avatarPresetColors.length; i++)
                        Center(
                          child: InkResponse(
                            radius: 34,
                            onTap: () =>
                                Navigator.pop(context, ProfileAvatar.preset(i)),
                            child: UserAvatar(
                              avatar: ProfileAvatar.preset(i),
                              name: '',
                              radius: 30,
                            ),
                          ),
                        ),
                    ],
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) => ThemedEmojiPicker(
                      height: constraints.maxHeight,
                      searchHeight: constraints.maxHeight,
                      showBackspace: false,
                      onEmojiSelected: (_, emoji) => Navigator.pop(
                        context,
                        ProfileAvatar.emoji(emoji.emoji),
                      ),
                    ),
                  ),
                  ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    children: [
                      _PhotoSourceCard(
                        icon: Icons.photo_library_rounded,
                        color: cs.primary,
                        title: 'Choose from gallery',
                        subtitle: 'Select an existing image from your device',
                        onTap: () =>
                            Navigator.pop(context, ImageSource.gallery),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _PhotoSourceCard(
                        icon: Icons.photo_camera_rounded,
                        color: cs.secondary,
                        title: 'Take a photo',
                        subtitle: 'Use your camera to take a new picture',
                        onTap: () =>
                            Navigator.pop(context, ImageSource.camera),
                      ),
                    ],
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
