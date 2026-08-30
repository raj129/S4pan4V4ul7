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
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pin_reauth_dialog.dart';
import '../../../core/widgets/main_scaffold_scope.dart';
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

    final selectedPhotos =
        _photos.where((p) => _selectedIds.contains(p.id)).toList();
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
      SnackBar(content: Text('${idsToDelete.length} photos moved to Secure Trash')),
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
      return const Center(child: CircularProgressIndicator());
    }
    if (_photos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 96,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 24),
            Text(
              'Your vault is empty',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Tap Import to add encrypted photos.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
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
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text('Sync is running in background'),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: _photos.length,
            itemBuilder: (context, index) {
              final photo = _photos[index];
              final isSelected = _selectedIds.contains(photo.id);
              return GestureDetector(
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: FutureBuilder(
                        future: widget.importManager.loadThumbnailBytes(
                          photo,
                        ),
                        builder: (context, snapshot) {
                          final bytes = snapshot.data;
                          if (snapshot.connectionState !=
                                  ConnectionState.done ||
                              bytes == null) {
                            return Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          }
                          return Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.image_outlined),
                            ),
                          );
                        },
                      ),
                    ),
                    if (isSelected)
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    if (isSelected)
                      const Positioned(
                        top: 4,
                        left: 4,
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    if (!_isSelectionMode)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(999),
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Colors.white,
                              size: 18,
                            ),
                            onPressed: () => _delete(photo),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BackupStatusBadge extends StatelessWidget {
  const _BackupStatusBadge({required this.synced});
  final bool synced;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
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
