import '../../domain/entities/vault_photo.dart';
import '../../domain/repositories/photo_repository.dart';

class InMemoryPhotoRepository implements PhotoRepository {
  final Map<String, VaultPhoto> _photos = {};

  @override
  Future<VaultPhoto?> getPhotoById(String photoId) async => _photos[photoId];

  @override
  Future<List<VaultPhoto>> listGalleryPage({
    required int page,
    required int pageSize,
    String? albumId,
    bool favoritesOnly = false,
  }) async {
    final start = page * pageSize;
    final filtered = _photos.values.where((p) {
      if (p.isTrashed) return false;
      if (albumId != null && p.albumId != albumId) return false;
      if (favoritesOnly && !p.favorite) return false;
      return true;
    }).toList()
      ..sort((a, b) => b.importedTimeMs.compareTo(a.importedTimeMs));
    if (start >= filtered.length) return const [];
    final end = (start + pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  @override
  Future<void> movePhotoToTrash(String photoId, {required int expiresAtMs}) async {
    final photo = _photos[photoId];
    if (photo == null) return;
    _photos[photoId] = VaultPhoto(
      id: photo.id,
      originalFilename: photo.originalFilename,
      encryptedFilePath: photo.encryptedFilePath,
      thumbnailPath: photo.thumbnailPath,
      wrappedDek: photo.wrappedDek,
      photoNonce: photo.photoNonce,
      thumbnailNonce: photo.thumbnailNonce,
      encryptionVersion: photo.encryptionVersion,
      checksumSha256: photo.checksumSha256,
      fileSize: photo.fileSize,
      mimeType: photo.mimeType,
      createdTimeMs: photo.createdTimeMs,
      importedTimeMs: photo.importedTimeMs,
      modifiedTimeMs: DateTime.now().millisecondsSinceEpoch,
      favorite: photo.favorite,
      isTrashed: true,
      albumId: photo.albumId,
      trashExpiresAtMs: expiresAtMs,
    );
  }

  @override
  Future<void> permanentlyDelete(String photoId) async {
    _photos.remove(photoId);
  }

  @override
  Future<void> restoreFromTrash(String photoId) async {
    final photo = _photos[photoId];
    if (photo == null) return;
    _photos[photoId] = VaultPhoto(
      id: photo.id,
      originalFilename: photo.originalFilename,
      encryptedFilePath: photo.encryptedFilePath,
      thumbnailPath: photo.thumbnailPath,
      wrappedDek: photo.wrappedDek,
      photoNonce: photo.photoNonce,
      thumbnailNonce: photo.thumbnailNonce,
      encryptionVersion: photo.encryptionVersion,
      checksumSha256: photo.checksumSha256,
      fileSize: photo.fileSize,
      mimeType: photo.mimeType,
      createdTimeMs: photo.createdTimeMs,
      importedTimeMs: photo.importedTimeMs,
      modifiedTimeMs: DateTime.now().millisecondsSinceEpoch,
      favorite: photo.favorite,
      isTrashed: false,
      albumId: photo.albumId,
      trashExpiresAtMs: null,
    );
  }

  @override
  Future<void> upsertPhoto(VaultPhoto photo) async {
    _photos[photo.id] = photo;
  }
}
