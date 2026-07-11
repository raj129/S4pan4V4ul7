import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../application/services/import_manager.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Review import')),
      body: Column(
        children: [
          ListTile(
            title: Text('${files.length} photo(s) selected'),
            subtitle: Text('Source: $source'),
          ),
          const Divider(height: 1),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
              ),
              itemCount: files.length,
              itemBuilder: (context, index) {
                return ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(files[index].path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_outlined),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      onImportQueued();
                      await importManager.enqueueImport(
                        files: files,
                        source: source,
                      );
                    },
                    child: const Text('Confirm import'),
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
