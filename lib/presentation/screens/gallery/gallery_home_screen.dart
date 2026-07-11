import 'package:flutter/material.dart';

import '../../../domain/entities/user_mode.dart';

/// Screen 8: Gallery home — empty state.
///
/// Shown after vault creation and on every subsequent launch once unlocked.
/// Import and settings are the primary actions. Backup badge is only shown
/// in Google-enabled mode.
class GalleryHomeScreen extends StatelessWidget {
  const GalleryHomeScreen({required this.mode, super.key});
  final UserMode mode;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Photo Vault'),
        actions: [
          if (mode == UserMode.googleEnabled)
            const _BackupStatusBadge(synced: false),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () {
              // TODO: navigate to settings screen
            },
          ),
        ],
      ),
      body: const _EmptyGalleryBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          // TODO: navigate to import screen
        },
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Import photos'),
      ),
    );
  }
}

class _EmptyGalleryBody extends StatelessWidget {
  const _EmptyGalleryBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 96,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 24),
          Text(
            'Your vault is empty',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Tap Import to add encrypted photos.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _BackupStatusBadge extends StatelessWidget {
  const _BackupStatusBadge({required this.synced});
  final bool synced;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Chip(
        avatar: Icon(
          synced ? Icons.cloud_done_rounded : Icons.cloud_upload_outlined,
          size: 16,
        ),
        label: Text(synced ? 'Backed up' : 'Backup pending'),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}
