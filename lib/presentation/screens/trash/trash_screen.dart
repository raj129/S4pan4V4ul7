import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../application/services/import_manager.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../../core/widgets/main_scaffold_scope.dart';
import '../../../domain/entities/vault_photo.dart';
import '../../../domain/repositories/photo_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../state/trash/trash_controller.dart';
import '../../widgets/confirm_dialog.dart';

/// The Bin screen: lists soft-deleted photos and lets the user restore or
/// permanently delete them, individually or in bulk.
///
/// All data loading and mutation now goes through [TrashController]; this
/// widget only renders that state and asks the user to confirm destructive
/// actions before delegating to the controller.
class TrashScreen extends StatefulWidget {
  const TrashScreen({
    required this.photoRepository,
    required this.importManager,
    super.key,
  });

  final PhotoRepository photoRepository;
  final ImportManager importManager;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  late final TrashController _controller = TrashController(
    photoRepository: widget.photoRepository,
    importManager: widget.importManager,
  );

  @override
  void initState() {
    super.initState();
    _controller.load();
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _restoreSelected() async {
    final count = _controller.selectedIds.length;
    if (count == 0) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore $count photos?',
      content: 'These photos will be moved back to the Gallery.',
      confirmLabel: 'Restore',
    );
    if (!confirmed) return;
    final restored = await _controller.restoreSelected();
    _showSnack('$restored photos restored');
  }

  Future<void> _permanentlyDeleteSelected() async {
    final count = _controller.selectedIds.length;
    if (count == 0) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Permanently delete $count photos?',
      content: 'This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    final deleted = await _controller.permanentlyDeleteSelected();
    _showSnack('$deleted photos permanently deleted');
  }

  Future<void> _restore(VaultPhoto photo) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore photo?',
      content: 'This photo will be moved back to the Gallery.',
      confirmLabel: 'Restore',
    );
    if (!confirmed) return;
    await _controller.restore(photo);
    _showSnack('Photo restored');
  }

  Future<void> _permanentlyDelete(VaultPhoto photo) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Permanently delete?',
      content: 'This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    await _controller.permanentlyDelete(photo);
  }

  Future<void> _emptyBin() async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Empty Bin?',
      content: 'All photos in the Bin will be permanently deleted.',
      confirmLabel: 'Empty',
    );
    if (confirmed) await _controller.emptyBin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _controller.isSelectionMode
          ? _SelectionAppBar(
              selectedCount: _controller.selectedIds.length,
              onClose: _controller.exitSelectionMode,
              onRestore: _restoreSelected,
              onDelete: _permanentlyDeleteSelected,
            )
          : _DefaultAppBar(
              hasPhotos: _controller.photos.isNotEmpty,
              onEmptyBin: _emptyBin,
            ),
      body: _TrashBody(
        controller: _controller,
        onRestore: _restore,
        onPermanentlyDelete: _permanentlyDelete,
      ),
    );
  }
}

class _DefaultAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _DefaultAppBar({required this.hasPhotos, required this.onEmptyBin});

  final bool hasPhotos;
  final VoidCallback onEmptyBin;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Bin'),
      leading: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () => openAppNavigationDrawer(context),
      ),
      actions: [
        if (hasPhotos)
          TextButton(onPressed: onEmptyBin, child: const Text('Empty')),
      ],
    );
  }
}

class _SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _SelectionAppBar({
    required this.selectedCount,
    required this.onClose,
    required this.onRestore,
    required this.onDelete,
  });

  final int selectedCount;
  final VoidCallback onClose;
  final VoidCallback onRestore;
  final VoidCallback onDelete;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: Text('$selectedCount selected'),
      leading: IconButton(icon: const Icon(Icons.close), onPressed: onClose),
      actions: [
        IconButton(
          icon: const Icon(Icons.restore),
          tooltip: 'Restore selected',
          onPressed: onRestore,
        ),
        IconButton(
          icon: const Icon(Icons.delete_forever),
          tooltip: 'Permanently delete selected',
          onPressed: onDelete,
        ),
      ],
    );
  }
}

class _TrashBody extends StatelessWidget {
  const _TrashBody({
    required this.controller,
    required this.onRestore,
    required this.onPermanentlyDelete,
  });

  final TrashController controller;
  final ValueChanged<VaultPhoto> onRestore;
  final ValueChanged<VaultPhoto> onPermanentlyDelete;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading) return const LoadingView();
    if (controller.photos.isEmpty) {
      return const EmptyView(
        icon: Icons.delete_outline,
        title: 'Trash is empty',
        subtitle: 'Deleted photos will appear here until they expire.',
      );
    }
    return MediaGrid(
      itemCount: controller.photos.length,
      itemBuilder: (context, index) {
        final photo = controller.photos[index];
        return _TrashTile(
          photo: photo,
          isSelected: controller.selectedIds.contains(photo.id),
          isSelectionMode: controller.isSelectionMode,
          loadThumbnail: () => controller.loadThumbnail(photo),
          onTap: () {
            if (controller.isSelectionMode) {
              controller.toggleSelection(photo.id);
              return;
            }
            context.push('/trash/photo', extra: photo);
          },
          onLongPress: () {
            if (!controller.isSelectionMode) {
              controller.toggleSelection(photo.id);
            }
          },
          onRestore: () => onRestore(photo),
          onPermanentlyDelete: () => onPermanentlyDelete(photo),
        );
      },
    );
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    required this.photo,
    required this.isSelected,
    required this.isSelectionMode,
    required this.loadThumbnail,
    required this.onTap,
    required this.onLongPress,
    required this.onRestore,
    required this.onPermanentlyDelete,
  });

  final VaultPhoto photo;
  final bool isSelected;
  final bool isSelectionMode;
  final Future<Uint8List?> Function() loadThumbnail;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onRestore;
  final VoidCallback onPermanentlyDelete;

  String get _daysLeftLabel {
    final expiresAtMs = photo.trashExpiresAtMs;
    if (expiresAtMs == null) return '';
    final expiry = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    final diff = expiry.difference(DateTime.now()).inDays;
    return diff <= 0 ? 'Expiring soon' : '$diff d left';
  }

  @override
  Widget build(BuildContext context) {
    final daysLeft = _daysLeftLabel;
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedScale(
        duration: AppDuration.fast,
        scale: isSelected ? 0.96 : 1,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: AppRadius.all(AppRadius.md),
              clipBehavior: Clip.antiAlias,
              child: FutureBuilder<Uint8List?>(
                future: loadThumbnail(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done ||
                      snapshot.data == null) {
                    return ColoredBox(color: scheme.surfaceContainerHighest);
                  }
                  return AnimatedOpacity(
                    duration: AppDuration.fast,
                    opacity: isSelected ? 0.55 : 0.72,
                    child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                  );
                },
              ),
            ),
            Positioned.fill(
              child: AnimatedContainer(
                duration: AppDuration.fast,
                decoration: BoxDecoration(
                  borderRadius: AppRadius.all(AppRadius.md),
                  border: Border.all(
                    color: isSelected ? semantic.danger : scheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                  color: isSelected
                      ? semantic.danger.withValues(alpha: 0.24)
                      : scheme.surfaceTint.withValues(alpha: 0),
                ),
              ),
            ),
            if (isSelectionMode)
              Positioned(
                top: AppSpacing.xs,
                left: AppSpacing.xs,
                child: AnimatedContainer(
                  duration: AppDuration.fast,
                  padding: const EdgeInsets.all(AppSpacing.xxs),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected
                        ? semantic.danger
                        : scheme.surface.withValues(alpha: 0.80),
                    border: Border.all(color: scheme.onPrimary),
                  ),
                  child: Icon(
                    isSelected ? Icons.check_rounded : Icons.circle_outlined,
                    color: isSelected ? scheme.onPrimary : semantic.danger,
                    size: 18,
                  ),
                ),
              ),
            if (daysLeft.isNotEmpty)
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.scrim.withValues(alpha: 0.56),
                    borderRadius: AppRadius.all(AppRadius.xs),
                  ),
                  child: Text(
                    daysLeft,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onInverseSurface,
                    ),
                  ),
                ),
              ),
            if (!isSelectionMode)
              Positioned(
                bottom: AppSpacing.xs,
                left: AppSpacing.xs,
                right: AppSpacing.xs,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _RoundIconButton(icon: Icons.restore, onPressed: onRestore),
                    _RoundIconButton(
                      icon: Icons.delete_forever,
                      onPressed: onPermanentlyDelete,
                      isDestructive: true,
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

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.onPressed,
    this.isDestructive = false,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = isDestructive ? context.semantic.danger : scheme.primary;
    return Material(
      color: scheme.scrim.withValues(alpha: 0.58),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Icon(icon, size: 18, color: accent),
        ),
      ),
    );
  }
}
