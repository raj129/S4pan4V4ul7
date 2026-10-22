import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:photo_vault/core/integrations/chat_vault_bridge.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';

/// A narrow vault attachment list for Android chat, not a general file browser.
/// Native memory-only playback may be supplied by the chat composition root.
class ChatSavedAttachmentsScreen extends StatefulWidget {
  const ChatSavedAttachmentsScreen({
    super.key,
    required this.bridge,
    this.onPreview,
  });

  final ChatVaultBridge bridge;
  final Future<void> Function(VaultPhoto item, Uint8List bytes)? onPreview;

  @override
  State<ChatSavedAttachmentsScreen> createState() =>
      _ChatSavedAttachmentsScreenState();
}

class _ChatSavedAttachmentsScreenState
    extends State<ChatSavedAttachmentsScreen> {
  late Future<List<VaultPhoto>> _items;
  Uint8List? _previewBytes;

  @override
  void initState() {
    super.initState();
    _items = widget.bridge.listSavedAttachments();
    widget.bridge.vaultSessionChanges.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!mounted) return;
    if (!widget.bridge.isUnlocked) {
      final bytes = _previewBytes;
      if (bytes != null) {
        MemoryImage(bytes).evict();
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    setState(() {
      _items = widget.bridge.isUnlocked
          ? widget.bridge.listSavedAttachments()
          : Future.value(const []);
    });
  }

  @override
  void dispose() {
    widget.bridge.vaultSessionChanges.removeListener(_sessionChanged);
    _previewBytes?.fillRange(0, _previewBytes!.length, 0);
    super.dispose();
  }

  Future<void> _open(VaultPhoto item) async {
    if (widget.onPreview != null) {
      Uint8List? bytes;
      try {
        bytes = await widget.bridge.readVaultPhoto(item);
        if (!mounted || !widget.bridge.isUnlocked) return;
        _previewBytes = bytes;
        await widget.onPreview!(item, bytes);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Unable to open attachment. Unlock the vault and retry.',
              ),
            ),
          );
        }
      } finally {
        bytes?.fillRange(0, bytes.length, 0);
        _previewBytes = null;
      }
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.originalFilename),
        content: Text(
          '${item.mimeType}\n${item.fileSize} bytes\n\n'
          'Stored encrypted in your vault. In-app preview is unavailable for this attachment.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Saved attachments'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: () => setState(() {
            _items = widget.bridge.listSavedAttachments();
          }),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: FutureBuilder<List<VaultPhoto>>(
      future: _items,
      builder: (context, snapshot) {
        if (!widget.bridge.isUnlocked || snapshot.hasError) {
          return const Center(
            child: Text('Unlock the vault to view saved attachments.'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Center(child: Text('No saved attachments.'));
        }
        return ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final icon = item.mimeType.startsWith('image/')
                ? Icons.image_outlined
                : item.mimeType.startsWith('video/')
                ? Icons.movie_outlined
                : item.mimeType.startsWith('audio/')
                ? Icons.audio_file_outlined
                : Icons.insert_drive_file_outlined;
            return ListTile(
              leading: Icon(icon),
              title: Text(item.originalFilename),
              subtitle: Text('${item.mimeType} · ${item.fileSize} bytes'),
              onTap: () => _open(item),
            );
          },
        );
      },
    ),
  );
}
