import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../application/services/import_manager.dart';
import '../../../domain/entities/vault_photo.dart';
import '../../../domain/entities/user_mode.dart';
import '../../../domain/repositories/photo_repository.dart';

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
    super.key,
  });
  final UserMode mode;
  final PhotoRepository photoRepository;
  final ImportManager importManager;
  final bool photoSyncEnabled;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Vault'),
        actions: [
          if (mode == UserMode.googleEnabled)
            const _BackupStatusBadge(synced: false),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              context.push('/settings');
            },
          ),
        ],
      ),
      body: _GalleryBody(
        photoRepository: photoRepository,
        importManager: importManager,
        photoSyncEnabled: photoSyncEnabled,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.push('/import');
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
  });
  final PhotoRepository photoRepository;
  final ImportManager importManager;
  final bool photoSyncEnabled;

  @override
  State<_GalleryBody> createState() => _GalleryBodyState();
}

class _GalleryBodyState extends State<_GalleryBody> {
  List<VaultPhoto> _photos = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.importManager.addListener(_onImportChanged);
    _load();
  }

  @override
  void dispose() {
    widget.importManager.removeListener(_onImportChanged);
    super.dispose();
  }

  void _onImportChanged() {
    final status = widget.importManager.progress.status;
    if (status == ImportJobStatus.running || status == ImportJobStatus.completed) {
      _load();
    }
  }

  Future<void> _load() async {
    final page = await widget.photoRepository.listGalleryPage(page: 0, pageSize: 1000);
    if (!mounted) return;
    setState(() {
      _photos = page;
      _loading = false;
    });
  }

  Future<void> _delete(VaultPhoto photo) async {
    final expiry = DateTime.now()
        .add(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await widget.photoRepository.movePhotoToTrash(
      photo.id,
      expiresAtMs: expiry,
    );
    await _load();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Moved to Secure Trash')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.importManager.progress;
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
    return Center(
      child: Column(
        children: [
          if (progress.status == ImportJobStatus.running)
            LinearProgressIndicator(value: progress.ratio),
          if (widget.photoSyncEnabled)
            const LinearProgressIndicator(minHeight: 2),
          if (progress.status == ImportJobStatus.running)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text('Importing ${progress.completed}/${progress.total}...'),
            ),
          if (widget.photoSyncEnabled)
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
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(photo.thumbnailPath),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.image_outlined),
                        ),
                      ),
                    ),
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
                );
              },
            ),
          ),
        ],
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
