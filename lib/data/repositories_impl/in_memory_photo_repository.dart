import 'dart:io';

import '../../domain/entities/vault_photo.dart';
import '../../domain/repositories/photo_repository.dart';

class InMemoryPhotoRepository implements PhotoRepository {
  final Map<String, VaultPhoto> _photos = {};

  @override
  Future<VaultPhoto?> getPhotoById(String photoId) async => _photos[photoId];

  @override
  Future<bool> existsChecksum(String checksumSha256) async {
    return _photos.values.any(
      (photo) => photo.checksumSha256 == checksumSha256,
    );
  }

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
    }).toList()..sort((a, b) => b.importedTimeMs.compareTo(a.importedTimeMs));
    if (start >= filtered.length) return const [];
    final end = (start + pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  @override
  Future<List<VaultPhoto>> listTrashPhotos() async {
    return _photos.values
        .where((p) => p.isTrashed)
        .toList()
      ..sort((a, b) => b.modifiedTimeMs.compareTo(a.modifiedTimeMs));
  }

  @override
  Future<void> movePhotoToTrash(
    String photoId, {
    required int expiresAtMs,
  }) async {
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
  Future<void> movePhotosToTrash(
    List<String> photoIds, {
    required int expiresAtMs,
  }) async {
    for (final id in photoIds) {
      await movePhotoToTrash(id, expiresAtMs: expiresAtMs);
    }
  }

  @override
  Future<void> deleteMetadataOnly(String photoId) async {
    _photos.remove(photoId);
  }

  @override
  Future<void> permanentlyDelete(String photoId) async {
    final photo = _photos.remove(photoId);
    if (photo == null) return;
    await _deleteIfExists(photo.encryptedFilePath);
    await _deleteIfExists(photo.thumbnailPath);
  }

  @override
  Future<void> permanentlyDeletePhotos(List<String> photoIds) async {
    for (final id in photoIds) {
      await permanentlyDelete(id);
    }
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
  Future<void> restorePhotosFromTrash(List<String> photoIds) async {
    for (final id in photoIds) {
      await restoreFromTrash(id);
    }
  }

  @override
  Future<void> upsertPhoto(VaultPhoto photo) async {
    _photos[photo.id] = photo;
  }

  Future<void> _deleteIfExists(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
