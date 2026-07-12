import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../application/services/import_manager.dart';
import '../../../domain/entities/vault_photo.dart';
import '../../../domain/repositories/photo_repository.dart';

/// Full-screen photo viewer with zoom/pan capability.
///
/// Shows encrypted photo in full resolution, allows zoom and pan,
/// and displays basic metadata (filename, size, etc.).
class GalleryPhotoViewerScreen extends StatefulWidget {
  const GalleryPhotoViewerScreen({
    required this.photo,
    required this.importManager,
    required this.photoRepository,
    super.key,
  });

  final VaultPhoto photo;
  final ImportManager importManager;
  final PhotoRepository photoRepository;

  @override
  State<GalleryPhotoViewerScreen> createState() =>
      _GalleryPhotoViewerScreenState();
}

class _GalleryPhotoViewerScreenState extends State<GalleryPhotoViewerScreen> {
  late final TransformationController _transformationController;
  Uint8List? _photoBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _transformationController = TransformationController();
    _loadPhoto();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadPhoto() async {
    try {
      final bytes = await widget.importManager.loadPhotoBytes(
        widget.photo,
      );
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load photo: $e';
        _loading = false;
      });
    }
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    appBar: AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.zoom_out_outlined),
            onPressed: _resetZoom,
            tooltip: 'Reset zoom',
          ),
          IconButton(
            icon: const Icon(Icons.info_outlined),
            onPressed: () => _showPhotoInfo(context),
            tooltip: 'Photo info',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
            tooltip: 'Delete',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.broken_image_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? 'Failed to load photo',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_photoBytes == null) {
      return const Center(
        child: Text('No photo data'),
      );
    }

    return Center(
      child: GestureDetector(
      onDoubleTap: () {
        if (_transformationController.value != Matrix4.identity()) {
          _resetZoom();
        } else {
          _transformationController.value = Matrix4.identity()..scale(2.0);
        }
      },
      child: InteractiveViewer(
        transformationController: _transformationController,
        minScale: 1,
        maxScale: 4,
        child: Container(
          color: Colors.black,
          child: Image.memory(
            _photoBytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, __) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.image_not_supported_outlined,
                    size: 64,
                    color: Colors.grey,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Cannot display photo',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ));
  }

  void _showPhotoInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => _PhotoInfoBottomSheet(photo: widget.photo),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete photo?'),
        content: const Text('This photo will be moved to Secure Trash.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final expiry = DateTime.now()
        .add(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await widget.photoRepository.movePhotoToTrash(
      widget.photo.id,
      expiresAtMs: expiry,
    );
    if (!context.mounted) return;
    context.pop();
  }
}

/// Bottom sheet showing photo metadata.
class _PhotoInfoBottomSheet extends StatelessWidget {
  const _PhotoInfoBottomSheet({required this.photo});

  final VaultPhoto photo;

  @override
  Widget build(BuildContext context) {
    final createdDate = DateTime.fromMillisecondsSinceEpoch(photo.createdTimeMs);
    final importedDate =
        DateTime.fromMillisecondsSinceEpoch(photo.importedTimeMs);
    final sizeStr = _formatBytes(photo.fileSize);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Photo Details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            _InfoRow(label: 'Filename', value: photo.originalFilename),
            _InfoRow(label: 'Size', value: sizeStr),
            _InfoRow(label: 'Type', value: photo.mimeType),
            _InfoRow(
              label: 'Created',
              value: _formatDateTime(createdDate),
            ),
            _InfoRow(
              label: 'Imported',
              value: _formatDateTime(importedDate),
            ),
            _InfoRow(label: 'ID', value: photo.id),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This photo is encrypted with AES-256-GCM',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

/// Single info row in the photo details sheet.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
