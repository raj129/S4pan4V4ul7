import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../application/services/import_manager.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({
    required this.importManager,
    required this.onOpenReview,
    this.autoOpenShareReview = false,
    super.key,
  });
  final ImportManager importManager;
  final void Function(List<XFile> files, String source) onOpenReview;
  final bool autoOpenShareReview;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isPicking = false;

  @override
  void initState() {
    super.initState();
    if (widget.autoOpenShareReview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final shared = widget.importManager.takePendingShareFiles();
        if (shared.isNotEmpty) {
          widget.onOpenReview(shared, 'share-intent');
        }
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No photos selected.')),
        );
        return;
      }
      widget.onOpenReview(files, 'gallery');
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
      widget.onOpenReview([file], 'camera');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open camera.')),
      );
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import photos')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose photos to import',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              'Selected photos will be encrypted and added to your vault.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isPicking ? null : _pickFromGallery,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(_isPicking ? 'Opening...' : 'Choose from gallery'),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _isPicking ? null : _pickFromCamera,
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Open camera'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                final shared = widget.importManager.takePendingShareFiles();
                if (shared.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No shared photos pending.')),
                  );
                  return;
                }
                widget.onOpenReview(shared, 'share-intent');
              },
              icon: const Icon(Icons.share_outlined),
              label: const Text('Review shared photos'),
            ),
            const SizedBox(height: 16),
            AnimatedBuilder(
              animation: widget.importManager,
              builder: (context, _) {
                final p = widget.importManager.progress;
                if (p.status == ImportJobStatus.running) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(value: p.ratio),
                      const SizedBox(height: 8),
                      Text('Importing ${p.completed}/${p.total} photo(s)...'),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
      ),
    );
  }
}
