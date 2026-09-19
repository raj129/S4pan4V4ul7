import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../application/services/import_manager.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../theme/app_spacing.dart';

Future<void> showImportBottomSheet(
  BuildContext context, {
  required ImportManager importManager,
  bool autoOpenShareReview = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.92,
      child: ImportScreen(
        importManager: importManager,
        autoOpenShareReview: autoOpenShareReview,
        onImportQueued: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}

class ImportBottomSheetLauncherScreen extends StatefulWidget {
  const ImportBottomSheetLauncherScreen({
    required this.importManager,
    required this.onClosed,
    this.autoOpenShareReview = false,
    super.key,
  });

  final ImportManager importManager;
  final VoidCallback onClosed;
  final bool autoOpenShareReview;

  @override
  State<ImportBottomSheetLauncherScreen> createState() =>
      _ImportBottomSheetLauncherScreenState();
}

class _ImportBottomSheetLauncherScreenState
    extends State<ImportBottomSheetLauncherScreen> {
  bool _opened = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showImportBottomSheet(
        context,
        importManager: widget.importManager,
        autoOpenShareReview: widget.autoOpenShareReview,
      );
      if (!mounted) return;
      widget.onClosed();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(
        context,
      ).colorScheme.surface.withValues(alpha: 0),
      body: const SizedBox.shrink(),
    );
  }
}

class _ImportTile extends StatelessWidget {
  const _ImportTile({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: AppRadius.all(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.file(
            File(file.path),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: const Icon(Icons.image_outlined),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: AppRadius.all(AppRadius.md),
              border: Border.all(color: scheme.outlineVariant),
            ),
          ),
        ],
      ),
    );
  }
}

class ImportScreen extends StatefulWidget {
  const ImportScreen({
    required this.importManager,
    required this.onImportQueued,
    this.autoOpenShareReview = false,
    super.key,
  });

  final ImportManager importManager;
  final VoidCallback onImportQueued;
  final bool autoOpenShareReview;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isPicking = false;
  bool _isQueueing = false;
  List<XFile> _selectedFiles = const [];
  String? _selectedSource;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = widget.importManager.pendingImportFiles;
      if (pending.isEmpty) return;
      setState(() {
        _selectedFiles = pending;
        _selectedSource =
            widget.importManager.pendingImportSource ?? 'share-intent';
      });
    });
  }

  Future<void> _pickFromGallery() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final files = await _picker.pickMultiImage();
      if (!mounted) return;
      if (files.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No photos selected.')));
        return;
      }
      setState(() {
        _selectedFiles = files;
        _selectedSource = 'gallery';
      });
      widget.importManager.setPendingImportSelection(
        files: files,
        source: 'gallery',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open gallery picker.')),
      );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  Future<void> _pickFromCamera() async {
    if (_isPicking) return;
    setState(() => _isPicking = true);
    try {
      final file = await _picker.pickImage(source: ImageSource.camera);
      if (!mounted) return;
      if (file == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No photo captured.')));
        return;
      }
      setState(() {
        _selectedFiles = [file];
        _selectedSource = 'camera';
      });
      widget.importManager.setPendingImportSelection(
        files: [file],
        source: 'camera',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Unable to open camera.')));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _startImport() {
    final source = _selectedSource;
    if (_selectedFiles.isEmpty || source == null || _isQueueing) return;
    setState(() => _isQueueing = true);
    final queuedFiles = widget.importManager.hasPendingImportSelection
        ? widget.importManager.takePendingImportSelection()
        : List<XFile>.from(_selectedFiles);
    widget.importManager.startBackgroundImport(
      files: queuedFiles,
      source: source,
    );
    widget.onImportQueued();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSelection = _selectedFiles.isNotEmpty && _selectedSource != null;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return AnimatedPadding(
      duration: AppDuration.fast,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasSelection
                          ? 'Review photos to encrypt'
                          : 'Import photos',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      widget.importManager.clearPendingImportSelection();
                      context.pop();
                    },
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                hasSelection
                    ? 'Review your photos below and hit Encrypt to secure them in your vault.'
                    : 'Choose photos to encrypt and add to your vault.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.lg),
              if (!hasSelection) ...[
                const SectionHeader(
                  'Sources',
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                ),
                SettingsCard(
                  margin: EdgeInsets.zero,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: Text(
                        _isPicking ? 'Opening...' : 'Choose from gallery',
                      ),
                      subtitle: const Text(
                        'Select one or more existing photos.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _isPicking ? null : _pickFromGallery,
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_camera_outlined),
                      title: const Text('Open camera'),
                      subtitle: const Text(
                        'Capture a new photo for the vault.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _isPicking ? null : _pickFromCamera,
                    ),
                  ],
                ),
              ] else ...[
                const SectionHeader(
                  'Selection',
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                ),
                SettingsCard(
                  margin: EdgeInsets.zero,
                  children: [
                    ListTile(
                      title: Text('${_selectedFiles.length} photo(s) selected'),
                      subtitle: Text('Source: $_selectedSource'),
                      trailing: TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedFiles = const [];
                            _selectedSource = null;
                            _isQueueing = false;
                          });
                          widget.importManager.clearPendingImportSelection();
                        },
                        child: const Text('Change'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Expanded(
                  child: MediaGrid(
                    padding: EdgeInsets.zero,
                    itemCount: _selectedFiles.length,
                    itemBuilder: (context, index) {
                      return _ImportTile(file: _selectedFiles[index]);
                    },
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AnimatedBuilder(
                animation: widget.importManager,
                builder: (context, _) {
                  final p = widget.importManager.progress;
                  if (p.status != ImportJobStatus.running) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: p.ratio),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Importing ${p.completed}/${p.total} photo(s)...',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  );
                },
              ),
              if (hasSelection)
                SafeArea(
                  top: false,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isQueueing
                              ? null
                              : () {
                                  widget.importManager
                                      .clearPendingImportSelection();
                                  context.pop();
                                },
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton(
                          onPressed: _isQueueing ? null : _startImport,
                          child: const Text('Encrypt'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
