import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../domain/entities/vault_photo.dart';
import '../../domain/repositories/photo_repository.dart';
import '../../storage/local_db/vault_database.dart' as drift_db;

/// Persistent photo repository backed by SQLite (drift).
///
/// Reads and writes photo metadata and encrypted file references to local DB.
/// Survives app restarts.
abstract class PersistentPhotoRepository implements PhotoRepository {
  /// Initialize DB connection (call once at app startup).
  Future<void> initialize();

  /// Close DB connection (call on app shutdown).
  Future<void> close();
}

/// Drift-backed implementation for persistent photo storage.
class PersistentPhotoRepositoryImpl implements PersistentPhotoRepository {
  PersistentPhotoRepositoryImpl();

  late drift_db.VaultDatabase _db;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _db = drift_db.VaultDatabase();
      _initialized = true;
      debugPrint('✅ PersistentPhotoRepository initialized with Drift');
    } catch (e) {
      debugPrint('❌ Failed to initialize PersistentPhotoRepository: $e');
      throw Exception('Failed to initialize database: $e');
    }
  }

  @override
  Future<void> close() async {
    if (!_initialized) return;
    try {
      await _db.close();
      _initialized = false;
      debugPrint('✅ PersistentPhotoRepository closed');
    } catch (e) {
      debugPrint('❌ Failed to close PersistentPhotoRepository: $e');
      throw Exception('Failed to close database: $e');
    }
  }

  void _requireInitialized() {
    if (!_initialized) {
      throw StateError(
        'PersistentPhotoRepository not initialized. Call initialize() first.',
      );
    }
  }

  /// Convert domain VaultPhoto to Drift VaultPhoto for storage.
  drift_db.VaultPhoto _toDriftPhoto(VaultPhoto photo) {
    return drift_db.VaultPhoto(
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
      modifiedTimeMs: photo.modifiedTimeMs,
      favorite: photo.favorite ? 1 : 0,
      isTrashed: photo.isTrashed ? 1 : 0,
      albumId: photo.albumId,
      trashExpiresAtMs: photo.trashExpiresAtMs,
      source: 'imported',
      syncStatus: 'local',
      backupStatus: 'not_backed_up',
      deletedTombstoneAtMs: null,
    );
  }

  /// Convert Drift VaultPhoto to domain VaultPhoto for use in app.
  VaultPhoto _todomainPhoto(drift_db.VaultPhoto photo) {
    return VaultPhoto(
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
      modifiedTimeMs: photo.modifiedTimeMs,
      favorite: photo.favorite == 1,
      isTrashed: photo.isTrashed == 1,
      albumId: photo.albumId,
      trashExpiresAtMs: photo.trashExpiresAtMs,
    );
  }

  @override
  Future<void> upsertPhoto(VaultPhoto photo) async {
    _requireInitialized();
    try {
      await _db.insertPhoto(_toDriftPhoto(photo));
      debugPrint('💾 Photo upserted: ${photo.id}');
    } catch (e) {
      debugPrint('❌ Failed to upsert photo: $e');
      rethrow;
    }
  }

  @override
  Future<VaultPhoto?> getPhotoById(String photoId) async {
    _requireInitialized();
    try {
      final driftPhoto = await _db.getPhotoById(photoId);
      return driftPhoto == null ? null : _todomainPhoto(driftPhoto);
    } catch (e) {
      debugPrint('❌ Failed to get photo: $e');
      return null;
    }
  }

  @override
  Future<bool> existsChecksum(String checksumSha256) async {
    _requireInitialized();
    try {
      return await _db.photoWithChecksumExists(checksumSha256);
    } catch (e) {
      debugPrint('❌ Failed to check checksum: $e');
      return false;
    }
  }

  @override
  Future<List<VaultPhoto>> listGalleryPage({
    required int page,
    required int pageSize,
    String? albumId,
    bool favoritesOnly = false,
  }) async {
    _requireInitialized();
    try {
      // For now, fetch all gallery photos and paginate in memory
      // TODO: Optimize with OFFSET/LIMIT in SQL query
      final allPhotos = await _db.getGalleryPhotos();
      
      var filtered = allPhotos.map(_todomainPhoto).toList();
      if (albumId != null) {
        filtered = filtered.where((p) => p.albumId == albumId).toList();
      }
      if (favoritesOnly) {
        filtered = filtered.where((p) => p.favorite).toList();
      }

      final start = page * pageSize;
      if (start >= filtered.length) return const [];
      
      final end = (start + pageSize).clamp(0, filtered.length);
      return filtered.sublist(start, end);
    } catch (e) {
      debugPrint('❌ Failed to list gallery page: $e');
      return [];
    }
  }

  @override
  Future<void> movePhotoToTrash(String photoId, {required int expiresAtMs}) async {
    _requireInitialized();
    try {
      await _db.movePhotoToTrash(photoId, expiresAtMs);
      debugPrint('🗑️  Photo moved to trash: $photoId');
    } catch (e) {
      debugPrint('❌ Failed to move to trash: $e');
      rethrow;
    }
  }

  @override
  Future<void> restoreFromTrash(String photoId) async {
    _requireInitialized();
    try {
      await _db.restorePhotoFromTrash(photoId);
      debugPrint('♻️  Photo restored: $photoId');
    } catch (e) {
      debugPrint('❌ Failed to restore: $e');
      rethrow;
    }
  }

  @override
  Future<void> permanentlyDelete(String photoId) async {
    _requireInitialized();
    try {
      // Get photo first to delete files
      final photo = await _db.getPhotoById(photoId);
      if (photo != null) {
        await _deleteIfExists(photo.encryptedFilePath);
        await _deleteIfExists(photo.thumbnailPath);
      }
      await _db.permanentlyDeletePhoto(photoId);
      debugPrint('🔥 Photo permanently deleted: $photoId');
    } catch (e) {
      debugPrint('❌ Failed to permanently delete: $e');
      rethrow;
    }
  }

  Future<void> _deleteIfExists(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️  Deleted file: $path');
      }
    } catch (e) {
      debugPrint('⚠️  Failed to delete file $path: $e');
    }
  }
}
