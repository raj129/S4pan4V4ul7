import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_photo_repository.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/features/backup/application/photo_hash_cache.dart';
import 'package:photo_vault/features/backup/application/vault_photo_backup_service.dart';
import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';

/// Reversible stand-in for backup encryption.
class _FakeCrypto implements ChatCryptoService {
  @override
  Future<Uint8List> encryptBackup(List<int> plain) async =>
      Uint8List.fromList([7, ...plain.map((b) => b ^ 0x5a)]);

  @override
  Future<Uint8List> decryptBackup(List<int> encrypted) async {
    if (encrypted.isEmpty || encrypted.first != 7) {
      throw const FormatException('bad key');
    }
    return Uint8List.fromList(encrypted.skip(1).map((b) => b ^ 0x5a).toList());
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _MemoryBlobStore implements BackupBlobStore {
  _MemoryBlobStore(this.label, {this.isCloud = false});

  @override
  final String label;
  @override
  final bool isCloud;
  @override
  bool get requiresNetwork => isCloud;

  final Map<String, Uint8List> blobs = {};
  int writes = 0;
  Object? readFailure;

  @override
  Future<void> writeFile(
    String name,
    File source, {
    bool interactive = false,
  }) async {
    writes++;
    blobs[name] = await source.readAsBytes();
  }

  @override
  Future<bool> readToFile(
    String name,
    File destination, {
    bool interactive = false,
  }) async {
    final failure = readFailure;
    if (failure != null) throw failure;
    final bytes = blobs[name];
    if (bytes == null) return false;
    await destination.writeAsBytes(bytes);
    return true;
  }

  @override
  Future<List<String>> list(String prefix, {bool interactive = false}) async =>
      blobs.keys.where((n) => n.startsWith(prefix)).toList();

  @override
  Future<void> delete(String name, {bool interactive = false}) async {
    blobs.remove(name);
  }
}

VaultPhoto _photo(String id, {required String dir}) => VaultPhoto(
  id: id,
  originalFilename: '$id.jpg',
  encryptedFilePath: '$dir/$id.photo',
  thumbnailPath: '$dir/$id.thumb',
  wrappedDek: '{"keyId":"k"}',
  photoNonce: 'pn-$id',
  thumbnailNonce: 'tn-$id',
  encryptionVersion: 1,
  checksumSha256: 'sum-$id',
  fileSize: 10,
  mimeType: 'image/jpeg',
  createdTimeMs: 1,
  importedTimeMs: 2,
  modifiedTimeMs: 3,
  favorite: true,
  isTrashed: false,
  albumId: 'album-1',
);

void main() {
  late Directory tmp;
  late InMemoryPhotoRepository photos;
  late InMemorySettingsRepository settings;
  late List<VaultPhoto> vault;
  late _MemoryBlobStore device;
  late _MemoryBlobStore cloud;
  late VaultPhotoBackupService service;
  late Directory restoreRoot;

  Future<void> writeSource(VaultPhoto photo, String body) async {
    await File(photo.encryptedFilePath).writeAsString('photo-$body');
    await File(photo.thumbnailPath).writeAsString('thumb-$body');
  }

  VaultPhotoBackupService buildService({
    required List<BackupBlobStore> stores,
    String vaultId = 'vault-1',
    InMemoryPhotoRepository? repository,
  }) {
    return VaultPhotoBackupService(
      stores: stores,
      photoRepository: repository ?? photos,
      listPhotos: () async => vault,
      crypto: _FakeCrypto(),
      settings: settings,
      currentUid: () => 'uid-1',
      networkAllowed: () async => true,
      currentVaultId: () async => vaultId,
      restoreRoot: () async => restoreRoot,
      tempRoot: () async => tmp,
    );
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vault_backup_test');
    restoreRoot = Directory('${tmp.path}/restored');
    photos = InMemoryPhotoRepository();
    settings = InMemorySettingsRepository();
    await settings.setBackupCloudEnabled(true);
    vault = [_photo('p1', dir: tmp.path), _photo('p2', dir: tmp.path)];
    await writeSource(vault[0], 'one');
    await writeSource(vault[1], 'two');
    device = _MemoryBlobStore('This device');
    cloud = _MemoryBlobStore('Google Drive', isCloud: true);
    service = buildService(stores: [device, cloud]);
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test(
    'backup uploads ciphertext and manifest to every active store',
    () async {
      final result = await service.backup();

      expect(result.photoCount, 2);
      expect(device.blobs.keys.where((n) => n.contains('photo_')).length, 2);
      expect(device.blobs.keys.where((n) => n.contains('thumb_')).length, 2);
      expect(
        cloud.blobs.keys.where((n) => n.endsWith('manifest.bin')).length,
        1,
      );
      expect(result.savedTo, containsAll(['This device', 'Google Drive']));
    },
  );

  test('second backup is incremental and writes nothing new', () async {
    await service.backup();
    final before = device.writes + cloud.writes;

    await service.backup();

    // Only the manifest is rewritten on each run.
    expect(device.writes + cloud.writes - before, 2);
  });

  test(
    'vaults use separate photo backup namespaces and due timestamps',
    () async {
      await service.backup();
      final oldCount = device.blobs.length;

      final otherVault = buildService(stores: [device], vaultId: 'vault-2');
      final result = await otherVault.backupIfDue(
        minAge: const Duration(days: 1),
      );

      expect(result, isNotNull);
      expect(device.blobs.length, greaterThan(oldCount));
      expect(await settings.getLastVaultPhotoBackupVaultId(), 'vault-2');
    },
  );

  test('restores legacy account-scoped photo backups', () async {
    await buildService(stores: [device]).backup();
    final accountHash = hash.sha256
        .convert(utf8.encode('uid-1'))
        .toString()
        .substring(0, 20);
    final legacyPrefix = 'vp_${accountHash}_';
    final scopedNames = device.blobs.keys.toList();
    final legacyBlobs = <String, Uint8List>{
      for (final name in scopedNames)
        '$legacyPrefix${name.substring(legacyPrefix.length + 21)}':
            device.blobs[name]!,
    };
    device.blobs
      ..clear()
      ..addAll(legacyBlobs);

    final result = await buildService(
      stores: [device],
      repository: InMemoryPhotoRepository(),
    ).restore();

    expect(result.restored, 2);
    expect(result.foundBackup, isTrue);
  });

  test('legacy photo backups still reject a different vault ID', () async {
    await buildService(stores: [device]).backup();
    final accountHash = hash.sha256
        .convert(utf8.encode('uid-1'))
        .toString()
        .substring(0, 20);
    final legacyPrefix = 'vp_${accountHash}_';
    final legacyBlobs = <String, Uint8List>{
      for (final entry in device.blobs.entries)
        '$legacyPrefix${entry.key.substring(legacyPrefix.length + 21)}':
            entry.value,
    };
    device.blobs
      ..clear()
      ..addAll(legacyBlobs);

    await expectLater(
      buildService(stores: [device], vaultId: 'vault-OTHER').restore(),
      throwsA(isA<VaultPhotoBackupMismatch>()),
    );
  });

  test('cloud off keeps the backup on this device only', () async {
    await settings.setBackupCloudEnabled(false);

    final result = await service.backup();

    expect(cloud.blobs, isEmpty);
    expect(result.skipped['Google Drive'], 'Cloud backup is off');
    expect(device.blobs, isNotEmpty);
  });

  test('restore recreates photos from the device copy first', () async {
    await service.backup();
    final before = {
      for (final p in vault)
        p.id: await File(p.encryptedFilePath).readAsString(),
    };

    // Simulate reinstall: the vault is empty, device copy still exists.
    final fresh = InMemoryPhotoRepository();
    final restoring = VaultPhotoBackupService(
      stores: [device, cloud],
      photoRepository: fresh,
      listPhotos: () async => const [],
      crypto: _FakeCrypto(),
      settings: settings,
      currentUid: () => 'uid-1',
      networkAllowed: () async => true,
      currentVaultId: () async => 'vault-1',
      restoreRoot: () async => restoreRoot,
      tempRoot: () async => tmp,
    );
    final result = await restoring.restore();

    expect(result.restored, 2);
    final restored = await fresh.getPhotoById('p1');
    expect(restored, isNotNull);
    expect(restored!.favorite, isTrue);
    expect(restored.albumId, 'album-1');
    expect(restored.encryptedFilePath, isNot(vault[0].encryptedFilePath));
    expect(await File(restored.encryptedFilePath).readAsString(), before['p1']);
  });

  test('restore skips photos already in the vault', () async {
    await service.backup();
    await photos.upsertPhoto(vault[0]);

    final result = await buildService(stores: [device]).restore();

    expect(result.alreadyPresent, 1);
    expect(result.restored, 1);
    expect(result.foundBackup, isTrue);
  });

  test(
    'restore repairs missing or damaged files for existing photos',
    () async {
      await service.backup();
      await File(vault[0].encryptedFilePath).delete();
      await File(vault[1].thumbnailPath).writeAsString('damaged-thumbnail');

      final result = await buildService(stores: [device]).restore();

      expect(result.restored, 2);
      expect(result.alreadyPresent, 0);
      final repairedPhoto = (await photos.getPhotoById('p1'))!;
      expect(
        await File(repairedPhoto.encryptedFilePath).readAsString(),
        'photo-one',
      );
      final repairedThumbnail = (await photos.getPhotoById('p2'))!;
      expect(
        await File(repairedThumbnail.thumbnailPath).readAsString(),
        'thumb-two',
      );
    },
  );

  test('photos removed from the vault are dropped from the backup', () async {
    await service.backup();
    vault = [vault[0]];

    await service.backup();

    expect(device.blobs.keys.any((n) => n.contains('p2')), isFalse);
    expect(device.blobs.keys.any((n) => n.contains('p1')), isTrue);
  });

  test('delete removes only the chosen copy', () async {
    await service.backup();

    await service.deleteBackup(device: true, cloud: false);

    expect(device.blobs, isEmpty);
    expect(cloud.blobs, isNotEmpty);
  });

  test(
    'photos with missing files are reported and left out of the manifest',
    () async {
      File(vault[1].encryptedFilePath).deleteSync();

      final result = await service.backup();

      expect(result.photoCount, 1);
      expect(result.missingCount, 1);
      final restored = await buildService(stores: [device]).restore();
      expect(restored.restored, 1);
    },
  );

  test(
    'restore rejects a blob whose hash does not match the manifest',
    () async {
      await service.backup();
      final photoBlob = device.blobs.keys.firstWhere(
        (n) => n.contains('photo_p1'),
      );
      device.blobs[photoBlob] = Uint8List.fromList([9, 9, 9]);

      final fresh = InMemoryPhotoRepository();
      final result = await VaultPhotoBackupService(
        stores: [device],
        photoRepository: fresh,
        listPhotos: () async => const [],
        crypto: _FakeCrypto(),
        settings: settings,
        currentUid: () => 'uid-1',
        networkAllowed: () async => true,
        currentVaultId: () async => 'vault-1',
        restoreRoot: () async => restoreRoot,
        tempRoot: () async => tmp,
      ).restore();

      expect(result.unavailable, 1);
      expect(await fresh.getPhotoById('p1'), isNull);
      expect(await fresh.getPhotoById('p2'), isNotNull);
    },
  );

  test('restore reads nothing from Google Drive when cloud is off', () async {
    await service.backup();
    await settings.setBackupCloudEnabled(false);
    device.blobs.clear();

    final fresh = InMemoryPhotoRepository();
    final result = await VaultPhotoBackupService(
      stores: [device, cloud],
      photoRepository: fresh,
      listPhotos: () async => const [],
      crypto: _FakeCrypto(),
      settings: settings,
      currentUid: () => 'uid-1',
      networkAllowed: () async => true,
      currentVaultId: () async => 'vault-1',
      restoreRoot: () async => restoreRoot,
      tempRoot: () async => tmp,
    ).restore();

    expect(result.restored, 0);
    expect(await fresh.getPhotoById('p1'), isNull);
  });

  test(
    'restore reports unreadable stores instead of claiming no backup',
    () async {
      await service.backup();
      device.readFailure = StateError('device file cannot be read');
      cloud.readFailure = StateError('Google Drive returned 403');

      await expectLater(
        buildService(stores: [device, cloud]).restore(interactive: true),
        throwsA(
          isA<VaultPhotoBackupReadException>()
              .having(
                (error) => error.toString(),
                'message',
                contains('This device'),
              )
              .having(
                (error) => error.toString(),
                'message',
                contains('Google Drive'),
              ),
        ),
      );
    },
  );

  test('restore does nothing when vault photos backup is turned off', () async {
    await service.backup();
    await settings.setBackupVaultPhotosEnabled(false);

    final fresh = InMemoryPhotoRepository();
    final result = await VaultPhotoBackupService(
      stores: [device],
      photoRepository: fresh,
      listPhotos: () async => const [],
      crypto: _FakeCrypto(),
      settings: settings,
      currentUid: () => 'uid-1',
      networkAllowed: () async => true,
      currentVaultId: () async => 'vault-1',
      restoreRoot: () async => restoreRoot,
      tempRoot: () async => tmp,
    ).restore();

    expect(result.restored, 0);
    expect(await fresh.getPhotoById('p1'), isNull);
  });

  test('restore does not find another vaults photo namespace', () async {
    await service.backup();

    final fresh = InMemoryPhotoRepository();
    final other = VaultPhotoBackupService(
      stores: [device],
      photoRepository: fresh,
      listPhotos: () async => const [],
      crypto: _FakeCrypto(),
      settings: settings,
      currentUid: () => 'uid-1',
      networkAllowed: () async => true,
      currentVaultId: () async => 'vault-OTHER',
      restoreRoot: () async => restoreRoot,
      tempRoot: () async => tmp,
    );

    final result = await other.restore();
    expect(result.foundBackup, isFalse);
    expect(result.restored, 0);
    expect(await fresh.getPhotoById('p1'), isNull);
  });

  test('backupIfDue skips when the last backup is recent', () async {
    final now = DateTime(2026, 11, 18, 12);
    await settings.setLastVaultPhotoBackupAt(
      now.subtract(const Duration(hours: 1)),
    );
    await settings.setLastVaultPhotoBackupVaultId('vault-1');
    final before = device.writes;

    final result = await service.backupIfDue(now: now);

    expect(result, isNull);
    expect(device.writes, before);
  });

  test('backupIfDue runs when the last backup is a day old', () async {
    final now = DateTime(2026, 11, 18, 12);
    await settings.setLastVaultPhotoBackupAt(
      now.subtract(const Duration(hours: 25)),
    );
    await settings.setLastVaultPhotoBackupVaultId('vault-1');

    final result = await service.backupIfDue(now: now);

    expect(result, isNotNull);
    expect(result!.photoCount, 2);
  });

  test('restore lands files in the vault root it is given', () async {
    await service.backup();

    final fresh = InMemoryPhotoRepository();
    await VaultPhotoBackupService(
      stores: [device],
      photoRepository: fresh,
      listPhotos: () async => const [],
      crypto: _FakeCrypto(),
      settings: settings,
      currentUid: () => 'uid-1',
      networkAllowed: () async => true,
      currentVaultId: () async => 'vault-1',
      restoreRoot: () async => restoreRoot,
      tempRoot: () async => tmp,
    ).restore();

    final restored = await fresh.getPhotoById('p1');
    expect(restored!.encryptedFilePath.startsWith(restoreRoot.path), isTrue);
  });

  test('an empty vault never replaces or clears an existing backup', () async {
    await service.backup();
    vault = [];

    final result = await service.backup();

    expect(result.photoCount, 0);
    expect(device.blobs.keys.any((n) => n.contains('photo_p1')), isTrue);
    final fresh = InMemoryPhotoRepository();
    final restore = await VaultPhotoBackupService(
      stores: [device],
      photoRepository: fresh,
      listPhotos: () async => const [],
      crypto: _FakeCrypto(),
      settings: settings,
      currentUid: () => 'uid-1',
      networkAllowed: () async => true,
      currentVaultId: () async => 'vault-1',
      restoreRoot: () async => restoreRoot,
      tempRoot: () async => tmp,
    ).restore();
    expect(restore.restored, 2);
  });

  test(
    'a run that hits its deadline keeps the old manifest and is marked incomplete',
    () async {
      await service.backup();
      final lastBefore = await settings.getLastVaultPhotoBackupAt();
      await File(vault[0].encryptedFilePath).writeAsString('changed');

      final result = await service.backup(
        deadline: DateTime.now().subtract(const Duration(seconds: 1)),
      );

      expect(result.completed, isFalse);
      expect(await settings.getLastVaultPhotoBackupAt(), lastBefore);
      expect(device.blobs.keys.any((n) => n.contains('photo_p2')), isTrue);
    },
  );

  test(
    'a manifest that cannot be decrypted reports a clear recovery error',
    () async {
      await service.backup();
      final manifest = device.blobs.keys.firstWhere(
        (n) => n.endsWith('manifest.bin'),
      );
      device.blobs[manifest] = Uint8List.fromList([1, 2, 3, 4]);

      await expectLater(
        buildService(stores: [device]).restore(),
        throwsA(
          isA<VaultPhotoBackupMismatch>().having(
            (e) => e.message,
            'message',
            contains('different account'),
          ),
        ),
      );
    },
  );

  test('the hash cache is written and reused on the next run', () async {
    final cacheFile = File('${tmp.path}/hash_cache.json');
    final cached = VaultPhotoBackupService(
      stores: [device],
      photoRepository: photos,
      listPhotos: () async => vault,
      crypto: _FakeCrypto(),
      settings: settings,
      currentUid: () => 'uid-1',
      networkAllowed: () async => true,
      currentVaultId: () async => 'vault-1',
      tempRoot: () async => tmp,
      hashCache: PhotoHashCache(file: () async => cacheFile),
    );

    await cached.backup();
    expect(await cacheFile.exists(), isTrue);
    final firstRun = jsonDecode(await cacheFile.readAsString()) as Map;
    expect(firstRun.length, 4);

    // Corrupt the cached value: a reused entry shows up in the manifest.
    await cacheFile.writeAsString(
      jsonEncode({for (final k in firstRun.keys) k as String: 'cached-hash'}),
    );
    final result = await cached.backup();

    expect(result.photoCount, 2);
    // The poisoned cache entries were trusted, so restore must reject them.
    final restored = await buildService(stores: [device]).restore();
    expect(restored.unavailable, 2);
  });
}
