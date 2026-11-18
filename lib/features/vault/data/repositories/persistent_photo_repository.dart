import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../domain/entities/vault_photo.dart';
import '../../domain/repositories/photo_repository.dart';
import 'package:photo_vault/core/storage/local_db/vault_database.dart'
    as drift_db;

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

/// Drift-backed photo storage filtered by the currently active vault ID.
///
/// Existing rows are assigned to the active vault during the schema migration.
class PersistentPhotoRepositoryImpl
    implements PersistentPhotoRepository, VaultAttachmentRepository {
  PersistentPhotoRepositoryImpl({
    required Future<String?> Function() currentVaultId,
    drift_db.VaultDatabase Function()? databaseFactory,
  }) : _currentVaultId = currentVaultId,
       _databaseFactory = databaseFactory ?? drift_db.VaultDatabase.new;

  late drift_db.VaultDatabase _db;
  final Future<String?> Function() _currentVaultId;
  final drift_db.VaultDatabase Function() _databaseFactory;
  bool _initialized = false;

  /// The open database, shared with other features that persist to the same
  /// file (the chat message cache). Null until [initialize] has run.
  ///
  /// Sharing one connection matters: opening a second `VaultDatabase` would
  /// point a separate connection at the same SQLite file, so writes made
  /// through one would not invalidate streams on the other.
  drift_db.VaultDatabase? get database => _initialized ? _db : null;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _db = _databaseFactory();
      _initialized = true;
      final vaultId = await _currentVaultId();
      if (vaultId != null) {
        await _db.assignLegacyPhotosToVault(vaultId);
      }
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

  Future<String?> _activeVaultId() async {
    _requireInitialized();
    return _currentVaultId();
  }

  Future<String> _requireVaultId() async {
    final vaultId = await _activeVaultId();
    if (vaultId == null || vaultId.isEmpty) {
      throw StateError('No active vault is available for photo storage.');
    }
    return vaultId;
  }

  /// Convert domain VaultPhoto to Drift VaultPhoto for storage.
  drift_db.VaultPhoto _toDriftPhoto(
    VaultPhoto photo, {
    required String vaultId,
  }) {
    return drift_db.VaultPhoto(
      vaultId: vaultId,
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
      final vaultId = await _requireVaultId();
      await _db.insertPhoto(_toDriftPhoto(photo, vaultId: vaultId));
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
      final vaultId = await _activeVaultId();
      if (vaultId == null) return null;
      final driftPhoto = await _db.getPhotoById(photoId, vaultId);
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
      final vaultId = await _activeVaultId();
      return vaultId != null &&
          await _db.photoWithChecksumExists(checksumSha256, vaultId);
    } catch (e) {
      debugPrint('❌ Failed to check checksum: $e');
      return false;
    }
  }

  @override
  Future<VaultPhoto?> findActiveChecksum(String checksum) async {
    _requireInitialized();
    final vaultId = await _activeVaultId();
    if (vaultId == null) return null;
    final rows =
        await (_db.select(_db.photos)..where(
              (p) =>
                  p.vaultId.equals(vaultId) &
                  p.checksumSha256.equals(checksum) &
                  p.isTrashed.equals(0),
            ))
            .get();
    return rows.isEmpty ? null : _todomainPhoto(rows.first);
  }

  @override
  Future<List<VaultPhoto>> listAttachments() async {
    _requireInitialized();
    final vaultId = await _activeVaultId();
    if (vaultId == null) return const [];
    final rows = await (_db.select(
      _db.photos,
    )..where((p) => p.vaultId.equals(vaultId) & p.isTrashed.equals(0))).get();
    return rows.map(_todomainPhoto).toList();
  }

  @override
  Future<List<VaultPhoto>> listGalleryPage({
    required int page,
    required int pageSize,
    int? offset,
    String? albumId,
    bool favoritesOnly = false,
  }) async {
    _requireInitialized();
    try {
      final vaultId = await _activeVaultId();
      if (vaultId == null) return const [];
      if (albumId != null || favoritesOnly) {
        // Fallback for complex filters until optimized in DB
        final allPhotos = await _db.getGalleryPhotos(vaultId: vaultId);
        var filtered = allPhotos.map(_todomainPhoto).toList();
        if (albumId != null) {
          filtered = filtered.where((p) => p.albumId == albumId).toList();
        }
        if (favoritesOnly) {
          filtered = filtered.where((p) => p.favorite).toList();
        }
        final start = offset ?? page * pageSize;
        if (start >= filtered.length) return const [];
        final end = (start + pageSize).clamp(0, filtered.length);
        return filtered.sublist(start, end);
      }

      final driftPhotos = await _db.getGalleryPhotos(
        vaultId: vaultId,
        limit: pageSize,
        offset: offset ?? page * pageSize,
      );
      return driftPhotos.map(_todomainPhoto).toList();
    } catch (e) {
      debugPrint('❌ Failed to list gallery page: $e');
      return [];
    }
  }

  @override
  Future<List<VaultPhoto>> listTrashPhotos() async {
    _requireInitialized();
    try {
      final vaultId = await _activeVaultId();
      if (vaultId == null) return const [];
      // For now fetching all, but could also paginate if needed
      final trashed = await _db.getTrashedPhotos(vaultId: vaultId);
      return trashed.map(_todomainPhoto).toList();
    } catch (e) {
      debugPrint('❌ Failed to list trash photos: $e');
      return [];
    }
  }

  @override
  Future<void> movePhotoToTrash(
    String photoId, {
    required int expiresAtMs,
  }) async {
    _requireInitialized();
    try {
      final vaultId = await _requireVaultId();
      await _db.movePhotoToTrash(photoId, expiresAtMs, vaultId);
      debugPrint('🗑️  Photo moved to trash: $photoId');
    } catch (e) {
      debugPrint('❌ Failed to move to trash: $e');
      rethrow;
    }
  }

  @override
  Future<void> movePhotosToTrash(
    List<String> photoIds, {
    required int expiresAtMs,
  }) async {
    _requireInitialized();
    try {
      final vaultId = await _requireVaultId();
      await _db.transaction(() async {
        for (final id in photoIds) {
          await _db.movePhotoToTrash(id, expiresAtMs, vaultId);
        }
      });
      debugPrint('🗑️  Batch moved to trash: ${photoIds.length} photos');
    } catch (e) {
      debugPrint('❌ Failed batch move to trash: $e');
      rethrow;
    }
  }

  @override
  Future<void> restoreFromTrash(String photoId) async {
    _requireInitialized();
    try {
      final vaultId = await _requireVaultId();
      await _db.restorePhotoFromTrash(photoId, vaultId);
      debugPrint('♻️  Photo restored: $photoId');
    } catch (e) {
      debugPrint('❌ Failed to restore: $e');
      rethrow;
    }
  }

  @override
  Future<void> restorePhotosFromTrash(List<String> photoIds) async {
    _requireInitialized();
    try {
      final vaultId = await _requireVaultId();
      await _db.transaction(() async {
        for (final id in photoIds) {
          await _db.restorePhotoFromTrash(id, vaultId);
        }
      });
      debugPrint('♻️  Batch restored from trash: ${photoIds.length} photos');
    } catch (e) {
      debugPrint('❌ Failed batch restore: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteMetadataOnly(String photoId) async {
    _requireInitialized();
    try {
      final vaultId = await _requireVaultId();
      await _db.permanentlyDeletePhoto(photoId, vaultId);
      debugPrint('🧹 Photo metadata removed: $photoId');
    } catch (e) {
      debugPrint('❌ Failed to remove photo metadata: $e');
      rethrow;
    }
  }

  @override
  Future<void> permanentlyDelete(String photoId) async {
    _requireInitialized();
    try {
      final vaultId = await _requireVaultId();
      // Get photo first to delete files
      final photo = await _db.getPhotoById(photoId, vaultId);
      if (photo != null) {
        await _deleteIfExists(photo.encryptedFilePath);
        await _deleteIfExists(photo.thumbnailPath);
      }
      await _db.permanentlyDeletePhoto(photoId, vaultId);
      debugPrint('🔥 Photo permanently deleted: $photoId');
    } catch (e) {
      debugPrint('❌ Failed to permanently delete: $e');
      rethrow;
    }
  }

  @override
  Future<void> permanentlyDeletePhotos(List<String> photoIds) async {
    _requireInitialized();
    try {
      final vaultId = await _requireVaultId();
      // Large file deletions should ideally be handled carefully
      await _db.transaction(() async {
        for (final id in photoIds) {
          final photo = await _db.getPhotoById(id, vaultId);
          if (photo != null) {
            // These file deletions are async and won't block the UI thread's event loop
            await _deleteIfExists(photo.encryptedFilePath);
            await _deleteIfExists(photo.thumbnailPath);
          }
          await _db.permanentlyDeletePhoto(id, vaultId);
        }
      });
      debugPrint('🔥 Batch permanently deleted: ${photoIds.length} photos');
    } catch (e) {
      debugPrint('❌ Failed batch permanent delete: $e');
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
