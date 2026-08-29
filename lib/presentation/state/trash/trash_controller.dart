import 'package:flutter/foundation.dart';

import '../../../application/services/import_manager.dart';
import '../../../domain/entities/vault_photo.dart';
import '../../../domain/repositories/photo_repository.dart';

/// Holds trash-list data and selection state, and performs the actual
/// repository mutations for restore/delete.
///
/// Extracted out of `_TrashScreenState` so the widget only has to render
/// state and ask the user to confirm destructive actions — it no longer
/// needs to know how photos are loaded, selected, or deleted.
class TrashController extends ChangeNotifier {
  TrashController({
    required PhotoRepository photoRepository,
    required ImportManager importManager,
  }) : _photoRepository = photoRepository,
       _importManager = importManager {
    _importManager.addListener(load);
  }

  final PhotoRepository _photoRepository;
  final ImportManager _importManager;

  List<VaultPhoto> _photos = [];
  final Set<String> _selectedIds = {};
  bool _isLoading = true;

  List<VaultPhoto> get photos => List.unmodifiable(_photos);
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);
  bool get isSelectionMode => _selectedIds.isNotEmpty;
  bool get isLoading => _isLoading;

  Future<void> load() async {
    final photos = await _photoRepository.listTrashPhotos();
    _photos = photos;
    _isLoading = false;
    notifyListeners();
  }

  Future<Uint8List?> loadThumbnail(VaultPhoto photo) {
    return _importManager.loadThumbnailBytes(photo);
  }

  void toggleSelection(String photoId) {
    if (!_selectedIds.add(photoId)) {
      _selectedIds.remove(photoId);
    }
    notifyListeners();
  }

  void exitSelectionMode() {
    _selectedIds.clear();
    notifyListeners();
  }

  /// Restores every selected photo and returns how many were restored.
  Future<int> restoreSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return 0;
    exitSelectionMode();
    await _photoRepository.restorePhotosFromTrash(ids);
    _importManager.notifyGalleryChanged();
    return ids.length;
  }

  /// Permanently deletes every selected photo and returns how many were
  /// deleted.
  Future<int> permanentlyDeleteSelected() async {
    final ids = _selectedIds.toList();
    if (ids.isEmpty) return 0;
    exitSelectionMode();
    await _photoRepository.permanentlyDeletePhotos(ids);
    await load();
    return ids.length;
  }

  Future<void> restore(VaultPhoto photo) async {
    await _photoRepository.restoreFromTrash(photo.id);
    _importManager.notifyGalleryChanged();
  }

  Future<void> permanentlyDelete(VaultPhoto photo) async {
    await _photoRepository.permanentlyDelete(photo.id);
    await load();
  }

  Future<void> emptyBin() async {
    if (_photos.isEmpty) return;
    await _photoRepository.permanentlyDeletePhotos(
      _photos.map((p) => p.id).toList(),
    );
    await load();
  }

  @override
  void dispose() {
    _importManager.removeListener(load);
    super.dispose();
  }
}
