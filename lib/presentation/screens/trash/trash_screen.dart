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

  Future<void> _restore(VaultPhoto photo) async {
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
      appBar: AppBar(
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
              onPressed: () {
                // Could implement "Empty Trash"
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
                    return Stack(
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
                                opacity: 0.6,
                                child: Image.memory(
                                  snapshot.data!,
                                  fit: BoxFit.cover,
                                ),
                              );
                            },
                          ),
                        ),
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
                    );
                  },
                ),
    );
  }
}
