import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../application/services/import_manager.dart';

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
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: SizedBox.shrink(),
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
    if (widget.autoOpenShareReview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final shared = widget.importManager.takePendingShareFiles();
        if (shared.isEmpty) return;
        setState(() {
          _selectedFiles = shared;
          _selectedSource = 'share-intent';
        });
      });
    }
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
    widget.importManager.startBackgroundImport(
      files: List<XFile>.from(_selectedFiles),
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
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Material(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      hasSelection ? 'Review import' : 'Import photos',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                hasSelection
                    ? 'Confirm import to return to the gallery immediately while encryption continues in the background.'
                    : 'Choose photos to encrypt and add to your vault.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              if (!hasSelection) ...[
                FilledButton.icon(
                  onPressed: _isPicking ? null : _pickFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: Text(
                    _isPicking ? 'Opening...' : 'Choose from gallery',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _isPicking ? null : _pickFromCamera,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: const Text('Open camera'),
                ),
              ] else ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('${_selectedFiles.length} photo(s) selected'),
                  subtitle: Text('Source: $_selectedSource'),
                  trailing: TextButton(
                    onPressed: () {
                      setState(() {
                        _selectedFiles = const [];
                        _selectedSource = null;
                        _isQueueing = false;
                      });
                    },
                    child: const Text('Change'),
                  ),
                ),
                Expanded(
                  child: GridView.builder(
                    padding: EdgeInsets.zero,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: _selectedFiles.length,
                    itemBuilder: (context, index) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_selectedFiles[index].path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: const Icon(Icons.image_outlined),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
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
                      const SizedBox(height: 8),
                      Text('Importing ${p.completed}/${p.total} photo(s)...'),
                      const SizedBox(height: 12),
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
                          onPressed: _isQueueing ? null : () => context.pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _isQueueing ? null : _startImport,
                          child: const Text('Confirm import'),
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
