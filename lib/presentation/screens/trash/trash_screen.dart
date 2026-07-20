import 'package:flutter/material.dart';
import '../../../domain/entities/vault_photo.dart';
import '../../../domain/repositories/photo_repository.dart';
import '../../../application/services/import_manager.dart';

class TrashScreen extends StatefulWidget {
  const TrashScreen({
    required this.photoRepository,
    required this.importManager,
    super.key,
  });

  final PhotoRepository photoRepository;
  final ImportManager importManager;

  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  List<VaultPhoto> _trashedPhotos = [];
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    widget.importManager.addListener(_loadTrash);
    _loadTrash();
  }

  @override
  void dispose() {
    widget.importManager.removeListener(_loadTrash);
    super.dispose();
  }

  Future<void> _loadTrash() async {
    final photos = await widget.photoRepository.listTrashPhotos();
    if (!mounted) return;
    setState(() {
      _trashedPhotos = photos;
      _isLoading = false;
    });
  }

  void _toggleSelection(String photoId) {
    setState(() {
      if (_selectedIds.contains(photoId)) {
        _selectedIds.remove(photoId);
        if (_selectedIds.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedIds.add(photoId);
        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _restoreSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Restore ${_selectedIds.length} photos?'),
        content: const Text('These photos will be moved back to the Gallery.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final idsToRestore = _selectedIds.toList();
    _exitSelectionMode();

    await widget.photoRepository.restorePhotosFromTrash(idsToRestore);
    widget.importManager.notifyGalleryChanged();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${idsToRestore.length} photos restored')),
    );
  }

  Future<void> _permanentlyDeleteSelected() async {
    if (_selectedIds.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permanently delete ${_selectedIds.length} photos?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final idsToDelete = _selectedIds.toList();
    _exitSelectionMode();

    await widget.photoRepository.permanentlyDeletePhotos(idsToDelete);
    _loadTrash();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${idsToDelete.length} photos permanently deleted')),
    );
  }

  Future<void> _restore(VaultPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore photo?'),
        content: const Text('This photo will be moved back to the Gallery.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await widget.photoRepository.restoreFromTrash(photo.id);
    widget.importManager.notifyGalleryChanged();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Photo restored')),
    );
  }

  Future<void> _permanentlyDelete(VaultPhoto photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.photoRepository.permanentlyDelete(photo.id);
    _loadTrash();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _isSelectionMode
          ? AppBar(
              title: Text('${_selectedIds.length} selected'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: _exitSelectionMode,
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.restore),
                  onPressed: _restoreSelected,
                  tooltip: 'Restore selected',
                ),
                IconButton(
                  icon: const Icon(Icons.delete_forever),
                  onPressed: _permanentlyDeleteSelected,
                  tooltip: 'Permanently delete selected',
                ),
              ],
            )
          : AppBar(
              title: const Text('Bin'),
              leading: IconButton(
                icon: const Icon(Icons.menu),
                onPressed: () {
                  Scaffold.of(context).openDrawer();
                },
              ),
              actions: [
                if (_trashedPhotos.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Empty Bin?'),
                          content: const Text('All photos in the Bin will be permanently deleted.'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Empty'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await widget.photoRepository.permanentlyDeletePhotos(
                          _trashedPhotos.map((p) => p.id).toList(),
                        );
                        _loadTrash();
                      }
                    },
                    child: const Text('Empty'),
                  ),
              ],
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _trashedPhotos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.delete_outline,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      const Text('Trash is empty'),
                    ],
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: _trashedPhotos.length,
                  itemBuilder: (context, index) {
                    final photo = _trashedPhotos[index];
                    final isSelected = _selectedIds.contains(photo.id);

                    // Calculate remaining days
                    String daysLeft = '';
                    if (photo.trashExpiresAtMs != null) {
                      final now = DateTime.now();
                      final expiry = DateTime.fromMillisecondsSinceEpoch(photo.trashExpiresAtMs!);
                      final diff = expiry.difference(now).inDays;
                      daysLeft = diff <= 0 ? 'Expiring soon' : '$diff d left';
                    }

                    return GestureDetector(
                      onTap: () {
                        if (_isSelectionMode) {
                          _toggleSelection(photo.id);
                        }
                      },
                      onLongPress: () {
                        if (!_isSelectionMode) {
                          _toggleSelection(photo.id);
                        }
                      },
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: FutureBuilder(
                              future: widget.importManager.loadThumbnailBytes(
                                photo,
                              ),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState !=
                                        ConnectionState.done ||
                                    snapshot.data == null) {
                                  return Container(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  );
                                }
                                return Opacity(
                                  opacity: isSelected ? 0.4 : 0.6,
                                  child: Image.memory(
                                    snapshot.data!,
                                    fit: BoxFit.cover,
                                  ),
                                );
                              },
                            ),
                          ),
                          if (isSelected)
                            Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          if (isSelected)
                            const Positioned(
                              top: 4,
                              left: 4,
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          if (daysLeft.isNotEmpty)
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  daysLeft,
                                  style: const TextStyle(color: Colors.white, fontSize: 10),
                                ),
                              ),
                            ),
                          if (!_isSelectionMode)
                            Positioned(
                              bottom: 4,
                              left: 4,
                              right: 4,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.black54,
                                    child: IconButton(
                                      iconSize: 14,
                                      icon: const Icon(Icons.restore,
                                          color: Colors.white),
                                      onPressed: () => _restore(photo),
                                    ),
                                  ),
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.black54,
                                    child: IconButton(
                                      iconSize: 14,
                                      icon: const Icon(Icons.delete_forever,
                                          color: Colors.white),
                                      onPressed: () => _permanentlyDelete(photo),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
