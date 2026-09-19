import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../application/services/import_manager.dart';
import '../../../core/widgets/app_state_views.dart';
import '../../../core/widgets/app_surfaces.dart';
import '../../theme/app_spacing.dart';

class ImportReviewScreen extends StatelessWidget {
  const ImportReviewScreen({
    required this.files,
    required this.source,
    required this.importManager,
    required this.onImportQueued,
    super.key,
  });

  final List<XFile> files;
  final String source;
  final ImportManager importManager;
  final VoidCallback onImportQueued;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return const Scaffold(
        body: EmptyView(
          icon: Icons.photo_library_outlined,
          title: 'No photos selected',
          subtitle: 'Choose photos before starting an import.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Review photos to encrypt')),
      body: Column(
        children: [
          SettingsCard(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            children: [
              ListTile(
                title: Text('${files.length} photo(s) selected'),
                subtitle: Text('Source: $source'),
              ),
            ],
          ),
          Expanded(
            child: MediaGrid(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: files.length,
              itemBuilder: (context, index) {
                return _ReviewTile(file: files[index]);
              },
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
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      onImportQueued();
                      await importManager.enqueueImport(
                        files: files,
                        source: source,
                      );
                    },
                    child: const Text('Encrypt'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewTile extends StatelessWidget {
  const _ReviewTile({required this.file});

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
