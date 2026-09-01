import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../application/services/chat_vault_bridge.dart';
import '../../../domain/entities/vault_photo.dart';

/// Grid of vault photos, for attaching one to a chat message.
///
/// Thumbnails are decrypted on demand rather than up front, so opening the
/// sheet does not decrypt an entire page of images the user may never scroll
/// to.
class VaultPickerSheet extends StatefulWidget {
  const VaultPickerSheet({super.key, required this.bridge});

  final ChatVaultBridge bridge;

  /// Show the picker and return the chosen photo, or null if dismissed.
  static Future<VaultPhoto?> show(
    BuildContext context, {
    required ChatVaultBridge bridge,
  }) {
    return showModalBottomSheet<VaultPhoto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VaultPickerSheet(bridge: bridge),
    );
  }

  @override
  State<VaultPickerSheet> createState() => _VaultPickerSheetState();
}

class _VaultPickerSheetState extends State<VaultPickerSheet> {
  late Future<List<VaultPhoto>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.bridge.listVaultPhotos();
  }

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.75,
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Send from vault',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<VaultPhoto>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Could not open vault: ${snap.error}'));
                }
                final photos = snap.data ?? const <VaultPhoto>[];
                if (photos.isEmpty) {
                  return const Center(child: Text('Your vault is empty.'));
                }
                return GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                  itemCount: photos.length,
                  itemBuilder: (context, i) {
                    final photo = photos[i];
                    return GestureDetector(
                      onTap: () => Navigator.pop(context, photo),
                      child: _VaultThumb(
                        key: ValueKey(photo.id),
                        photo: photo,
                        bridge: widget.bridge,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VaultThumb extends StatefulWidget {
  const _VaultThumb({super.key, required this.photo, required this.bridge});

  final VaultPhoto photo;
  final ChatVaultBridge bridge;

  @override
  State<_VaultThumb> createState() => _VaultThumbState();
}

class _VaultThumbState extends State<_VaultThumb> {
  late final Future<Uint8List?> _thumb = widget.bridge.thumbnailOf(
    widget.photo,
  );

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: FutureBuilder<Uint8List?>(
        future: _thumb,
        builder: (context, snap) {
          final bytes = snap.data;
          if (bytes == null || bytes.isEmpty) {
            return const ColoredBox(
              color: Colors.black12,
              child: Center(
                child: Icon(Icons.image_outlined, color: Colors.white54),
              ),
            );
          }
          return Image.memory(bytes, fit: BoxFit.cover);
        },
      ),
    );
  }
}
