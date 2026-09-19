import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../application/services/import_manager.dart';
import '../../../application/services/pin_validator.dart';
import '../../../application/services/vault_session.dart';
import '../../../application/usecases/export_photo_usecase.dart';
import '../../../application/usecases/unlock_vault_usecase.dart';
import '../../../domain/entities/user_mode.dart';
import '../../../domain/entities/vault_photo.dart';
import '../../../domain/repositories/photo_repository.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pin_reauth_dialog.dart';
import '../../../core/widgets/main_scaffold_scope.dart';
import '../../theme/app_spacing.dart';
import '../import/import_screen.dart';

/// Screen 8: Gallery home — empty state.
///
/// Shown after vault creation and on every subsequent launch once unlocked.
/// Import and settings are the primary actions. Backup badge is only shown
/// in Google-enabled mode.
class GalleryHomeScreen extends StatelessWidget {
  const GalleryHomeScreen({
    required this.mode,
    required this.photoRepository,
    required this.importManager,
    required this.photoSyncEnabled,
    this.vaultSession,
    this.exportPhotoUseCase,
    this.unlockVaultUseCase,
    this.pinValidator,
    super.key,
  });
  final UserMode mode;
  final PhotoRepository photoRepository;
  final ImportManager importManager;
  final bool photoSyncEnabled;
  final VaultSession? vaultSession;
  final ExportPhotoUseCase? exportPhotoUseCase;
  final UnlockVaultUseCase? unlockVaultUseCase;
  final PinValidator? pinValidator;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photos'),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => openAppNavigationDrawer(context),
        ),
        actions: [
          if (mode == UserMode.googleEnabled)
            const _BackupStatusBadge(synced: false),
        ],
      ),
      body: _GalleryBody(
        photoRepository: photoRepository,
        importManager: importManager,
        photoSyncEnabled: photoSyncEnabled,
        vaultSession: vaultSession,
        exportPhotoUseCase: exportPhotoUseCase,
        unlockVaultUseCase: unlockVaultUseCase,
        pinValidator: pinValidator,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showImportBottomSheet(context, importManager: importManager);
        },
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Import photos'),
      ),
    );
  }
}

class _GalleryBody extends StatefulWidget {
  const _GalleryBody({
    required this.photoRepository,
    required this.importManager,
    required this.photoSyncEnabled,
    this.vaultSession,
    this.exportPhotoUseCase,
    this.unlockVaultUseCase,
    this.pinValidator,
  });
  final PhotoRepository photoRepository;
  final ImportManager importManager;
  final bool photoSyncEnabled;
  final VaultSession? vaultSession;
  final ExportPhotoUseCase? exportPhotoUseCase;
  final UnlockVaultUseCase? unlockVaultUseCase;
  final PinValidator? pinValidator;

  @override
  State<_GalleryBody> createState() => _GalleryBodyState();
}

class _GalleryBodyState extends State<_GalleryBody> {
  List<VaultPhoto> _photos = const [];
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  bool _loading = true;
  int _lastSeenGalleryRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.importManager.addListener(_onImportChanged);
    widget.vaultSession?.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.importManager.removeListener(_onImportChanged);
    widget.vaultSession?.removeListener(_load);
    super.dispose();
  }

  void _onImportChanged() {
    final revision = widget.importManager.galleryEventRevision;
    if (revision == _lastSeenGalleryRevision) {
      if (mounted) {
        setState(() {});
      }
      return;
    }
    _lastSeenGalleryRevision = revision;
    final importedPhotoId = widget.importManager.lastImportedPhotoId;
    if (importedPhotoId == null) {
      _load();
      return;
    }
    _insertOrRefreshPhoto(importedPhotoId);
  }

  Future<void> _load() async {
    final page = await widget.photoRepository.listGalleryPage(
      page: 0,
      pageSize: 1000,
    );
    if (!mounted) return;
    setState(() {
      _photos = page;
      _loading = false;
    });
  }

  Future<void> _insertOrRefreshPhoto(String photoId) async {
    final photo = await widget.photoRepository.getPhotoById(photoId);
    if (!mounted || photo == null || photo.isTrashed) return;
    setState(() {
      final updated = _photos.where((item) => item.id != photo.id).toList();
      updated.insert(0, photo);
      _photos = updated;
      _loading = false;
    });
  }

  void _toggleSelection(String photoId) {
    setState(() {
      if (_selectedIds.contains(photoId)) {
        _selectedIds.remove(photoId);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(photoId);
        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _exportSelected() async {
    if (_selectedIds.isEmpty || widget.exportPhotoUseCase == null) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Export ${_selectedIds.length} photo(s)?',
      content:
          'This will export plaintext photos to your Downloads folder (PhotoVault_Exports). Continue?',
      confirmLabel: 'Export',
    );

    if (!confirmed || !mounted) return;

    if (widget.unlockVaultUseCase != null && widget.pinValidator != null) {
      final allowed = await requirePinReauth(
        context: context,
        unlockVaultUseCase: widget.unlockVaultUseCase!,
        pinValidator: widget.pinValidator!,
        actionLabel: 'export selected photos',
      );
      if (!allowed || !mounted) return;
    }

    final selectedPhotos = _photos
        .where((p) => _selectedIds.contains(p.id))
        .toList();
    _exitSelectionMode();

    int successCount = 0;
    for (final photo in selectedPhotos) {
      try {
        await widget.exportPhotoUseCase!.execute(photo);
        successCount++;
      } catch (e) {
        debugPrint('Failed to export photo ${photo.id}: $e');
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Exported $successCount photo(s) to Downloads folder'),
      ),
    );
  }

  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${_selectedIds.length} photos?',
      content: 'These photos will be moved to Secure Trash.',
      confirmLabel: 'Delete',
    );

    if (!confirmed) return;

    final idsToDelete = _selectedIds.toList();
    _exitSelectionMode();

    final expiry = DateTime.now()
        .add(const Duration(days: 30))
        .millisecondsSinceEpoch;

    await widget.photoRepository.movePhotosToTrash(
      idsToDelete,
      expiresAtMs: expiry,
    );

    widget.importManager.notifyGalleryChanged();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${idsToDelete.length} photos moved to Secure Trash'),
      ),
    );
  }

  Future<void> _delete(VaultPhoto photo) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete photo?',
      content: 'This photo will be moved to Secure Trash.',
      confirmLabel: 'Delete',
    );
    if (!confirmed) return;
    final expiry = DateTime.now()
        .add(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await widget.photoRepository.movePhotoToTrash(
      photo.id,
      expiresAtMs: expiry,
    );
    widget.importManager.notifyGalleryChanged();
    if (!mounted) return;
    setState(() {
      _photos = _photos.where((item) => item.id != photo.id).toList();
    });
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Moved to Secure Trash')));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const LoadingView(message: 'Loading encrypted photos...');
    }
    if (_photos.isEmpty) {
      return EmptyView(
        icon: Icons.photo_library_outlined,
        title: 'Your vault is empty',
        subtitle: 'Tap Import to add encrypted photos.',
        actionLabel: 'Import photos',
        actionIcon: Icons.add_photo_alternate_outlined,
        onAction: () {
          showImportBottomSheet(context, importManager: widget.importManager);
        },
      );
    }
    return Column(
      children: [
        if (_isSelectionMode)
          AppBar(
            backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
            title: Text('${_selectedIds.length} selected'),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: _exitSelectionMode,
            ),
            actions: [
              if (widget.exportPhotoUseCase != null)
                IconButton(
                  icon: const Icon(Icons.file_download_outlined),
                  onPressed: _exportSelected,
                  tooltip: 'Export selected',
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: _deleteSelected,
                tooltip: 'Delete selected',
              ),
            ],
          ),
        if (widget.photoSyncEnabled && !_isSelectionMode)
          const LinearProgressIndicator(minHeight: 2),
        if (widget.photoSyncEnabled && !_isSelectionMode)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Text(
              'Sync is running in background',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        Expanded(
          child: MediaGrid(
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final isSelected = _selectedIds.contains(photo.id);
              return _GalleryTile(
                photo: photo,
                isSelected: isSelected,
                isSelectionMode: _isSelectionMode,
                loadThumbnail: () =>
                    widget.importManager.loadThumbnailBytes(photo),
                onTap: () {
                  if (_isSelectionMode) {
                    _toggleSelection(photo.id);
                  } else {
                    context.push('/gallery/photo', extra: photo);
                  }
                },
                onLongPress: () {
                  if (!_isSelectionMode) {
                    _toggleSelection(photo.id);
                  }
                },
                onDelete: () => _delete(photo),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _GalleryTile extends StatelessWidget {
  const _GalleryTile({
    required this.photo,
    required this.isSelected,
    required this.isSelectionMode,
    required this.loadThumbnail,
    required this.onTap,
    required this.onLongPress,
    required this.onDelete,
  });

  final VaultPhoto photo;
  final bool isSelected;
  final bool isSelectionMode;
  final Future<Uint8List?> Function() loadThumbnail;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                  final bytes = snapshot.data;
                  if (snapshot.connectionState != ConnectionState.done ||
                      bytes == null) {
                    return ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: const Center(
                        child: SizedBox.square(
                          dimension: AppSpacing.xl,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    );
                  }
                  return Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_outlined),
                    ),
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
                    color: isSelected ? scheme.primary : scheme.outlineVariant,
                    width: isSelected ? 2 : 1,
                  ),
                  color: isSelected
                      ? scheme.primary.withValues(alpha: 0.22)
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
                        ? scheme.primary
                        : scheme.surface.withValues(alpha: 0.80),
                    border: Border.all(color: scheme.onPrimary),
                  ),
                  child: Icon(
                    isSelected ? Icons.check_rounded : Icons.circle_outlined,
                    color: isSelected ? scheme.onPrimary : scheme.primary,
                    size: 18,
                  ),
                ),
              ),
            if (!isSelectionMode)
              Positioned(
                top: AppSpacing.xs,
                right: AppSpacing.xs,
                child: Material(
                  color: scheme.scrim.withValues(alpha: 0.54),
                  borderRadius: AppRadius.all(AppRadius.pill),
                  child: IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      Icons.delete_outline,
                      color: scheme.onInverseSurface,
                      size: 18,
                    ),
                    onPressed: onDelete,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BackupStatusBadge extends StatelessWidget {
  const _BackupStatusBadge({required this.synced});
  final bool synced;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      child: Chip(
        avatar: Icon(
          synced ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
          size: 16,
        ),
        label: Text(synced ? 'Backed up' : 'Backup pending'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
