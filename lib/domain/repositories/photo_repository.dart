import '../entities/vault_photo.dart';

abstract class PhotoRepository {
  Future<void> upsertPhoto(VaultPhoto photo);
  Future<VaultPhoto?> getPhotoById(String photoId);
  Future<bool> existsChecksum(String checksumSha256);
  Future<List<VaultPhoto>> listGalleryPage({
    required int page,
    required int pageSize,
    String? albumId,
    bool favoritesOnly = false,
  });
  Future<List<VaultPhoto>> listTrashPhotos();
  Future<void> movePhotoToTrash(String photoId, {required int expiresAtMs});
  Future<void> restoreFromTrash(String photoId);
  Future<void> deleteMetadataOnly(String photoId);
  Future<void> permanentlyDelete(String photoId);
}
