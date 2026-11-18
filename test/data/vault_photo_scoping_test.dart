import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/storage/local_db/vault_database.dart';
import 'package:photo_vault/features/vault/data/repositories/persistent_photo_repository.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart'
    as domain;
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late VaultDatabase database;

  setUp(() {
    database = VaultDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('photo rows with the same ID remain isolated by vault ID', () async {
    await database.insertPhoto(_photo('shared-id', 'vault-a', 'a.jpg'));
    await database.insertPhoto(_photo('shared-id', 'vault-b', 'b.jpg'));

    expect(
      (await database.getPhotoById('shared-id', 'vault-a'))?.originalFilename,
      'a.jpg',
    );
    expect(
      (await database.getPhotoById('shared-id', 'vault-b'))?.originalFilename,
      'b.jpg',
    );
    expect(
      (await database.getGalleryPhotos(
        vaultId: 'vault-a',
      )).map((photo) => photo.originalFilename),
      ['a.jpg'],
    );
  });

  test(
    'legacy photo rows can be assigned to their existing active vault',
    () async {
      await database.insertPhoto(
        _photo('legacy-photo', '__legacy__', 'legacy.jpg'),
      );

      await database.assignLegacyPhotosToVault('existing-vault');

      expect(
        (await database.getPhotoById(
          'legacy-photo',
          'existing-vault',
        ))?.originalFilename,
        'legacy.jpg',
      );
      expect(
        await database.getPhotoById('legacy-photo', 'other-vault'),
        isNull,
      );
    },
  );

  test('schema v6 photos migrate without losing rows', () async {
    final directory = await Directory.systemTemp.createTemp(
      'photo-vault-migration-',
    );
    final path = '${directory.path}${Platform.pathSeparator}vault.sqlite';
    final initial = VaultDatabase.forTesting(NativeDatabase(File(path)));
    await initial.select(initial.photos).get();
    await initial.insertPhoto(
      _photo('legacy-photo', '__legacy__', 'legacy.jpg'),
    );
    await initial.close();

    final raw = sqlite.sqlite3.open(path);
    raw.execute('ALTER TABLE photos RENAME TO photos_before_v7');
    raw.execute('''
      CREATE TABLE photos (
        id TEXT NOT NULL PRIMARY KEY,
        original_filename TEXT NOT NULL,
        created_time_ms INTEGER NOT NULL,
        imported_time_ms INTEGER NOT NULL,
        modified_time_ms INTEGER NOT NULL,
        source TEXT NOT NULL,
        album_id TEXT,
        favorite INTEGER NOT NULL DEFAULT 0,
        encrypted_file_path TEXT NOT NULL,
        thumbnail_path TEXT NOT NULL,
        thumbnail_nonce TEXT NOT NULL,
        photo_nonce TEXT NOT NULL,
        wrapped_dek TEXT NOT NULL,
        encryption_version INTEGER NOT NULL,
        sync_status TEXT NOT NULL,
        backup_status TEXT NOT NULL,
        checksum_sha256 TEXT NOT NULL,
        file_size INTEGER NOT NULL,
        mime_type TEXT NOT NULL,
        is_trashed INTEGER NOT NULL DEFAULT 0,
        trash_expires_at_ms INTEGER,
        deleted_tombstone_at_ms INTEGER
      )
    ''');
    raw.execute('''
      INSERT INTO photos (
        id, original_filename, created_time_ms, imported_time_ms,
        modified_time_ms, source, album_id, favorite, encrypted_file_path,
        thumbnail_path, thumbnail_nonce, photo_nonce, wrapped_dek,
        encryption_version, sync_status, backup_status, checksum_sha256,
        file_size, mime_type, is_trashed, trash_expires_at_ms,
        deleted_tombstone_at_ms
      )
      SELECT id, original_filename, created_time_ms, imported_time_ms,
        modified_time_ms, source, album_id, favorite, encrypted_file_path,
        thumbnail_path, thumbnail_nonce, photo_nonce, wrapped_dek,
        encryption_version, sync_status, backup_status, checksum_sha256,
        file_size, mime_type, is_trashed, trash_expires_at_ms,
        deleted_tombstone_at_ms
      FROM photos_before_v7
    ''');
    raw.execute('DROP TABLE photos_before_v7');
    raw.execute('PRAGMA user_version = 6');
    raw.close();

    final migrated = VaultDatabase.forTesting(NativeDatabase(File(path)));
    final rows = await migrated.select(migrated.photos).get();
    expect(rows, hasLength(1));
    expect(rows.single.vaultId, '__legacy__');
    expect(rows.single.originalFilename, 'legacy.jpg');
    await migrated.close();
    await directory.delete(recursive: true);
  });

  test('persistent repository only reads the active vault photos', () async {
    var activeVaultId = 'vault-a';
    final repository = PersistentPhotoRepositoryImpl(
      currentVaultId: () async => activeVaultId,
      databaseFactory: () => VaultDatabase.forTesting(NativeDatabase.memory()),
    );
    await repository.initialize();
    await repository.upsertPhoto(_domainPhoto('shared-id', 'a.jpg'));

    activeVaultId = 'vault-b';
    await repository.upsertPhoto(_domainPhoto('shared-id', 'b.jpg'));
    expect(
      (await repository.getPhotoById('shared-id'))?.originalFilename,
      'b.jpg',
    );
    expect(
      (await repository.listAttachments()).map(
        (photo) => photo.originalFilename,
      ),
      ['b.jpg'],
    );

    activeVaultId = 'vault-a';
    expect(
      (await repository.getPhotoById('shared-id'))?.originalFilename,
      'a.jpg',
    );
    await repository.close();
  });

  test(
    'repository assigns migrated legacy photos to the existing vault',
    () async {
      final oldDatabase = VaultDatabase.forTesting(NativeDatabase.memory());
      await oldDatabase.insertPhoto(
        _photo('legacy-photo', '__legacy__', 'legacy.jpg'),
      );
      final repository = PersistentPhotoRepositoryImpl(
        currentVaultId: () async => 'existing-vault',
        databaseFactory: () => oldDatabase,
      );

      await repository.initialize();

      expect(
        (await repository.getPhotoById('legacy-photo'))?.originalFilename,
        'legacy.jpg',
      );
      await repository.close();
    },
  );
}

VaultPhoto _photo(String id, String vaultId, String name) => VaultPhoto(
  vaultId: vaultId,
  id: id,
  originalFilename: name,
  createdTimeMs: 1,
  importedTimeMs: 1,
  modifiedTimeMs: 1,
  source: 'imported',
  albumId: null,
  favorite: 0,
  encryptedFilePath: '$vaultId/$id.enc',
  thumbnailPath: '$vaultId/$id-thumb.enc',
  thumbnailNonce: 'thumb-nonce',
  photoNonce: 'photo-nonce',
  wrappedDek: '{}',
  encryptionVersion: 1,
  syncStatus: 'local',
  backupStatus: 'not_backed_up',
  checksumSha256: 'sum-$vaultId',
  fileSize: 1,
  mimeType: 'image/jpeg',
  isTrashed: 0,
  trashExpiresAtMs: null,
  deletedTombstoneAtMs: null,
);

domain.VaultPhoto _domainPhoto(String id, String name) => domain.VaultPhoto(
  id: id,
  originalFilename: name,
  encryptedFilePath: '$name.enc',
  thumbnailPath: '$name-thumb.enc',
  wrappedDek: '{}',
  photoNonce: 'photo-nonce',
  thumbnailNonce: 'thumbnail-nonce',
  encryptionVersion: 1,
  checksumSha256: name,
  fileSize: 1,
  mimeType: 'image/jpeg',
  createdTimeMs: 1,
  importedTimeMs: 1,
  modifiedTimeMs: 1,
  favorite: false,
  isTrashed: false,
  albumId: null,
);
