import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../application/services/profile_service.dart';
import 'package:photo_vault/core/app/external_activity_guard.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/entities/profile_avatar.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../widgets/user_avatar.dart';

/// Edit the name and picture other people see in chat.
///
/// Changes are staged: picking an avatar only previews it, and nothing is
/// stored or uploaded until Save, which returns to the chat list.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.me, required this.service});

  final ChatUser me;
  final ProfileService service;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final TextEditingController _name;
  late final String _initialName;
  late final ProfileAvatar _initialAvatar;
  late ProfileAvatar _avatar;

  /// A newly picked photo, shown from memory until it is uploaded on Save.
  Uint8List? _pickedPhoto;
  bool _saving = false;

  ProfileService get _service => widget.service;

  @override
  void initState() {
    super.initState();
    _initialName = _service.profile?.displayName ?? widget.me.displayName;
    _initialAvatar = _service.profile?.avatar ?? widget.me.avatar;
    _avatar = _initialAvatar;
    _name = TextEditingController(text: _initialName)
      ..addListener(() => setState(() {}));
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
    if (_saving || !_valid) return;
    FocusScope.of(context).unfocus();
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    setState(() => _saving = true);
    try {
      await _service.saveProfile(
        me: widget.me,
        displayName: _name.text.trim(),
        avatar: _avatar,
        photoBytes: _pickedPhoto,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Could not save your profile. Check your connection and retry.');
      return;
    }
    // The messenger outlives this route, so the confirmation shows on the
    // chat list the user lands on.
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Profile saved.')));
    if (router.canPop()) {
      router.pop();
    } else {
      router.go('/chat');
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
    final shownName = _name.text.trim().isEmpty
        ? _initialName
        : _name.text.trim();
    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmDiscard()) navigator.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          actions: [
            TextButton(
              onPressed: _dirty && _valid && !_saving ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.xl,
                horizontal: AppSpacing.lg,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _saving ? null : _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.primary.withValues(alpha: 0.35),
                              width: 2.5,
                            ),
                          ),
                          child: _pickedPhoto != null
                              ? CircleAvatar(
                                  radius: 54,
                                  backgroundImage: MemoryImage(_pickedPhoto!),
                                )
                              : UserAvatar(
                                  avatar: _avatar,
                                  name: shownName,
                                  radius: 54,
                                ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.camera_alt_rounded,
                              size: 18,
                              color: theme.colorScheme.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    shownName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.alternate_email_rounded,
                          size: 13,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.me.email,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickAvatar,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Change picture'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
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
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: _dirty && _valid && !_saving ? _save : null,
              child: _saving
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text('Saving…'),
                      ],
                    )
                  : const Text('Save'),
            ),
          ],
        ),
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
    final height = MediaQuery.sizeOf(context).height * 0.65;
    return SizedBox(
      height: height,
      child: DefaultTabController(
        length: 3,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(
                  icon: Icon(Icons.palette_outlined),
                  text: 'Default',
                ),
                Tab(
                  icon: Icon(Icons.emoji_emotions_outlined),
                  text: 'Emoji',
                ),
                Tab(
                  icon: Icon(Icons.photo_camera_outlined),
                  text: 'Photo',
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  GridView.count(
                    crossAxisCount: 4,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    mainAxisSpacing: AppSpacing.md,
                    crossAxisSpacing: AppSpacing.md,
                    children: [
                      InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(
                          context,
                          const ProfileAvatar.initials(),
                        ),
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
                            radius: 30,
                          ),
                        ),
                      ),
                      for (var i = 0; i < avatarPresetColors.length; i++)
                        InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () =>
                              Navigator.pop(context, ProfileAvatar.preset(i)),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: avatarPresetColors[i % avatarPresetColors.length]
                                      .withValues(alpha: 0.3),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: UserAvatar(
                              avatar: ProfileAvatar.preset(i),
                              name: '',
                              radius: 30,
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
                          color: const Color(0xFF7C4DFF),
                          title: 'Choose from gallery',
                          subtitle: 'Select an existing image from your device',
                          onTap: () =>
                              Navigator.pop(context, ImageSource.gallery),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _PhotoSourceCard(
                          icon: Icons.photo_camera_rounded,
                          color: const Color(0xFFE91E63),
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
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
