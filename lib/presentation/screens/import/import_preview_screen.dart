import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../application/services/import_manager.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../theme/app_spacing.dart';

class ImportPreviewScreen extends StatefulWidget {
  const ImportPreviewScreen({
    required this.file,
    required this.importManager,
    required this.onConfirm,
    required this.onCancel,
    super.key,
  });

  final XFile file;
  final ImportManager importManager;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  State<ImportPreviewScreen> createState() => _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends State<ImportPreviewScreen> {
  late Future<Uint8List> _previewFuture;

  @override
  void initState() {
    super.initState();
    _previewFuture = widget.file.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Photo preview'), centerTitle: true),
      body: FutureBuilder<Uint8List>(
        future: _previewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LoadingView(message: 'Loading preview...');
          }
          if (snapshot.hasError) {
            return ErrorView(
              title: 'Preview unavailable',
              message: 'Failed to load preview: ${snapshot.error}',
            );
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return const EmptyView(
              icon: Icons.image_not_supported_outlined,
              title: 'No image data',
            );
          }
          return Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'File: ${widget.file.name}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Size: ${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onCancel,
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        onPressed: widget.onConfirm,
                        child: const Text('Confirm & import'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
