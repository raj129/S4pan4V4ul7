import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../application/usecases/export_photo_usecase.dart';
import '../../../application/usecases/unlock_vault_usecase.dart';
import '../../../application/services/import_manager.dart';
import '../../../application/services/pin_validator.dart';
import '../../../application/services/vault_session.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../../domain/entities/vault_photo.dart';
import '../../../domain/repositories/photo_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/pin_reauth_dialog.dart';

/// Full-screen photo viewer with zoom/pan capability.
///
/// Shows encrypted photo in full resolution, allows zoom and pan,
/// and displays basic metadata (filename, size, etc.).
class GalleryPhotoViewerScreen extends StatefulWidget {
  const GalleryPhotoViewerScreen({
    required this.photo,
    required this.importManager,
    required this.photoRepository,
    required this.exportPhotoUseCase,
    required this.unlockVaultUseCase,
    required this.pinValidator,
    this.isTrashPreview = false,
    this.onRestore,
    this.onPermanentlyDelete,
    super.key,
  });

  final VaultPhoto photo;
  final ImportManager importManager;
  final PhotoRepository photoRepository;
  final ExportPhotoUseCase exportPhotoUseCase;
  final UnlockVaultUseCase unlockVaultUseCase;
  final PinValidator pinValidator;
  final bool isTrashPreview;
  final Future<void> Function()? onRestore;
  final Future<void> Function()? onPermanentlyDelete;

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
      final bytes = await widget.importManager.loadPhotoBytes(widget.photo);
      if (!mounted) return;
      setState(() {
        _photoBytes = bytes;
        _loading = false;
        _error = null;
      });
    } on VaultLockedException {
      if (!mounted) return;
      setState(() {
        _error = 'Vault session is locked. Please unlock to view.';
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
    final viewerTheme = _darkViewerTheme(context);
    return Theme(
      data: viewerTheme,
      child: Builder(
        builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          if (_error != null && _error!.contains('locked')) {
            return Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => context.pop(),
                ),
              ),
              body: ErrorView(
                title: 'Vault locked',
                message: _error!,
                onRetry: _loadPhoto,
              ),
            );
          }

          return Scaffold(
            backgroundColor: scheme.scrim,
            appBar: AppBar(
              backgroundColor: scheme.scrim.withValues(alpha: 0.50),
              foregroundColor: scheme.onInverseSurface,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => context.pop(),
              ),
              actions: [
                if (widget.isTrashPreview) ...[
                  IconButton(
                    icon: const Icon(Icons.restore_outlined),
                    onPressed: () => _restoreFromTrash(context),
                    tooltip: 'Restore',
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_forever_outlined),
                    onPressed: () => _permanentlyDeleteFromTrash(context),
                    tooltip: 'Delete permanently',
                  ),
                ] else ...[
                  IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    onPressed: () => _exportPhoto(context),
                    tooltip: 'Export to Downloads',
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
              ],
            ),
            extendBodyBehindAppBar: true,
            body: _buildBody(context),
          );
        },
      ),
    );
  }

  ThemeData _darkViewerTheme(BuildContext context) {
    final base = Theme.of(context);
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: Brightness.dark,
    );
    // Full-bleed media chrome is intentionally dark regardless of app theme.
    return base.copyWith(
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.scrim,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.scrim.withValues(alpha: 0.50),
        foregroundColor: scheme.onInverseSurface,
        elevation: 0,
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const LoadingView(message: 'Decrypting photo...');
    }

    if (_error != null) {
      return ErrorView(
        title: 'Unable to load photo',
        message: _error ?? 'Failed to load photo',
        onRetry: _loadPhoto,
      );
    }

    if (_photoBytes == null) {
      return const EmptyView(
        icon: Icons.image_not_supported_outlined,
        title: 'No photo data',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onDoubleTapDown: (details) {
            _handleDoubleTap(details.localPosition, constraints);
          },
          child: InteractiveViewer(
            transformationController: _transformationController,
            minScale: 1.0,
            maxScale: 5.0,
            boundaryMargin: EdgeInsets.zero,
            clipBehavior: Clip.none,
            child: SizedBox(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              child: Image.memory(
                _photoBytes!,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const ErrorView(
                  title: 'Unsupported image',
                  message: 'Cannot display photo',
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _handleDoubleTap(Offset localPosition, BoxConstraints constraints) {
    if (_transformationController.value != Matrix4.identity()) {
      _resetZoom();
    } else {
      // Zoom in towards the tap location
      final x = -localPosition.dx * 1.5;
      final y = -localPosition.dy * 1.5;
      final zoomed = Matrix4.identity()
        ..translateByDouble(x, y, 0, 1.0)
        ..scaleByDouble(2.5, 2.5, 1.0, 1.0);

      setState(() {
        _transformationController.value = zoomed;
      });
    }
  }

  void _showPhotoInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => _PhotoInfoBottomSheet(photo: widget.photo),
    );
  }

  Future<void> _exportPhoto(BuildContext context) async {
    final approved = await showConfirmDialog(
      context,
      title: 'Export decrypted photo?',
      content:
          'This will export plaintext outside the vault. Continue only if you trust the destination.',
      confirmLabel: 'Continue',
    );
    if (!approved || !context.mounted) return;

    final allowed = await requirePinReauth(
      context: context,
      unlockVaultUseCase: widget.unlockVaultUseCase,
      pinValidator: widget.pinValidator,
      actionLabel: 'export this photo',
    );
    if (!allowed) return;

    try {
      final path = await widget.exportPhotoUseCase.execute(widget.photo);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Photo exported to Downloads: ${path.split('/').last}'),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to export photo: $e')));
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete photo?',
      content: 'This photo will be moved to Secure Trash.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
    final expiry = DateTime.now()
        .add(const Duration(days: 30))
        .millisecondsSinceEpoch;
    await widget.photoRepository.movePhotoToTrash(
      widget.photo.id,
      expiresAtMs: expiry,
    );
    widget.importManager.notifyGalleryChanged();
    if (!context.mounted) return;
    context.pop();
  }

  Future<void> _restoreFromTrash(BuildContext context) async {
    if (widget.onRestore == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Restore photo?',
      content: 'This photo will be moved back to the gallery.',
      confirmLabel: 'Restore',
    );
    if (!confirmed || !context.mounted) return;
    await widget.onRestore!();
  }

  Future<void> _permanentlyDeleteFromTrash(BuildContext context) async {
    if (widget.onPermanentlyDelete == null) return;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete permanently?',
      content: 'This action cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!confirmed || !context.mounted) return;
    await widget.onPermanentlyDelete!();
  }
}

/// Bottom sheet showing photo metadata.
class _PhotoInfoBottomSheet extends StatelessWidget {
  const _PhotoInfoBottomSheet({required this.photo});

  final VaultPhoto photo;

  @override
  Widget build(BuildContext context) {
    final createdDate = DateTime.fromMillisecondsSinceEpoch(
      photo.createdTimeMs,
    );
    final importedDate = DateTime.fromMillisecondsSinceEpoch(
      photo.importedTimeMs,
    );
    final sizeStr = _formatBytes(photo.fileSize);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Photo Details',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            SettingsCard(
              margin: EdgeInsets.zero,
              children: [
                _InfoRow(label: 'Filename', value: photo.originalFilename),
                _InfoRow(label: 'Size', value: sizeStr),
                _InfoRow(label: 'Type', value: photo.mimeType),
                _InfoRow(label: 'Created', value: _formatDateTime(createdDate)),
                _InfoRow(
                  label: 'Imported',
                  value: _formatDateTime(importedDate),
                ),
                _InfoRow(label: 'ID', value: photo.id),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            InfoBanner(
              icon: Icons.lock_outlined,
              title: 'Encrypted',
              message: 'This photo is encrypted with AES-256-GCM.',
            ),
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
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Text(
          value,
          style: theme.textTheme.bodyMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
