import '../entities/vault_photo.dart';

/// Narrow generic-attachment queries; gallery callers remain image-only.
abstract class VaultAttachmentRepository {
  Future<VaultPhoto?> findActiveChecksum(String checksum);
  Future<List<VaultPhoto>> listAttachments();
}

abstract class PhotoRepository {
  Future<void> upsertPhoto(VaultPhoto photo);
  Future<VaultPhoto?> getPhotoById(String photoId);
  Future<bool> existsChecksum(String checksumSha256);
  Future<List<VaultPhoto>> listGalleryPage({
    required int page,
    required int pageSize,
    int? offset,
    String? albumId,
    bool favoritesOnly = false,
  });
  Future<List<VaultPhoto>> listTrashPhotos();
  Future<void> movePhotoToTrash(String photoId, {required int expiresAtMs});
  Future<void> movePhotosToTrash(
    List<String> photoIds, {
    required int expiresAtMs,
  });
  Future<void> restoreFromTrash(String photoId);
  Future<void> restorePhotosFromTrash(List<String> photoIds);
  Future<void> deleteMetadataOnly(String photoId);
  Future<void> permanentlyDelete(String photoId);
  Future<void> permanentlyDeletePhotos(List<String> photoIds);
}
