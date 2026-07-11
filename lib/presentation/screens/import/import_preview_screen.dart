import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../application/services/import_manager.dart';

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
      appBar: AppBar(
        title: const Text('Photo preview'),
        centerTitle: true,
      ),
      body: FutureBuilder<Uint8List>(
        future: _previewFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text('Failed to load preview: ${snapshot.error}'),
                ],
              ),
            );
          }
          final bytes = snapshot.data;
          if (bytes == null || bytes.isEmpty) {
            return const Center(child: Text('No image data'));
          }
          return Column(
            children: [
              Expanded(
                child: InteractiveViewer(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'File: ${widget.file.name}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Size: ${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onCancel,
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
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
