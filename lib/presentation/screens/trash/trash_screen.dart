import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../../../application/services/import_manager.dart';
import '../../../domain/entities/vault_photo.dart';
import '../../../domain/repositories/photo_repository.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../../core/widgets/main_scaffold_scope.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
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
      return const EmptyView(icon: Icons.delete_outline, title: 'Trash is empty');
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: controller.photos.length,
      itemBuilder: (context, index) {
        final photo = controller.photos[index];
        return _TrashTile(
          photo: photo,
          isSelected: controller.selectedIds.contains(photo.id),
          isSelectionMode: controller.isSelectionMode,
          loadThumbnail: () => controller.loadThumbnail(photo),
          onTap: () {
            if (controller.isSelectionMode) controller.toggleSelection(photo.id);
          },
          onLongPress: () {
            if (!controller.isSelectionMode) controller.toggleSelection(photo.id);
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
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FutureBuilder<Uint8List?>(
              future: loadThumbnail(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done ||
                    snapshot.data == null) {
                  return Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  );
                }
                return Opacity(
                  opacity: isSelected ? 0.4 : 0.6,
                  child: Image.memory(snapshot.data!, fit: BoxFit.cover),
                );
              },
            ),
          ),
          if (isSelected)
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          if (isSelected)
            const Positioned(
              top: 4,
              left: 4,
              child: Icon(Icons.check_circle, color: Colors.white, size: 20),
            ),
          if (daysLeft.isNotEmpty)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(daysLeft, style: const TextStyle(color: Colors.white, fontSize: 10)),
              ),
            ),
          if (!isSelectionMode)
            Positioned(
              bottom: 4,
              left: 4,
              right: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundIconButton(icon: Icons.restore, onPressed: onRestore),
                  _RoundIconButton(icon: Icons.delete_forever, onPressed: onPermanentlyDelete),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 14,
      backgroundColor: Colors.black54,
      child: IconButton(
        iconSize: 14,
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }
}
