import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:photo_vault/features/backup/application/backup_coordinator.dart';
import 'package:photo_vault/features/backup/application/backup_progress.dart';
import 'package:photo_vault/features/backup/application/photo_hash_cache.dart';
import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/vault/application/services/vault_storage_root.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';
import 'package:photo_vault/features/vault/domain/repositories/photo_repository.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

/// Outcome of a vault photo backup run.
class VaultPhotoBackupResult {
  const VaultPhotoBackupResult({
    required this.photoCount,
    required this.missingCount,
    required this.savedTo,
    required this.skipped,
    this.completed = true,
  });

  /// Photos that were backed up and verified.
  final int photoCount;

  /// Photos left out because their encrypted files are missing on this device.
  final int missingCount;
  final List<String> savedTo;

  /// Store label → reason it was not written.
  final Map<String, String> skipped;

  /// False when the run stopped at its deadline. The previous manifest is kept
  /// and the next run continues.
  final bool completed;
}

/// Outcome of a vault photo restore run.
class VaultPhotoRestoreResult {
  const VaultPhotoRestoreResult({
    required this.restored,
    required this.alreadyPresent,
    required this.unavailable,
    this.foundBackup = false,
    this.failures = const [],
  });

  final int restored;
  final int alreadyPresent;
  final bool foundBackup;

  /// Listed in the backup but not found (or failing verification) in any store.
  final int unavailable;

  /// Stores that could not be read while trying to restore.
  final List<String> failures;
}

class VaultPhotoBackupReadException implements Exception {
  const VaultPhotoBackupReadException(this.failures);

  final List<String> failures;

  @override
  String toString() =>
      'Could not read a vault photo backup: ${failures.join('; ')}';
}

/// Thrown when a backup cannot be opened with this vault or account.
class VaultPhotoBackupMismatch implements Exception {
  const VaultPhotoBackupMismatch(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Backs up and restores vault photos (encrypted ciphertext plus metadata).
///
/// Photos are already encrypted per file, so the blobs are copied as they are;
/// they never need the vault unlocked, which is what lets the nightly job run.
/// The manifest is encrypted with the account backup key and records the vault
/// ID, so restoring into a different vault is refused. Work is incremental,
/// files are streamed and verified on disk, and every operation runs through
/// [BackupCoordinator] so backup, restore, and delete never interleave.
class VaultPhotoBackupService {
  VaultPhotoBackupService({
    required List<BackupBlobStore> stores,
    required PhotoRepository photoRepository,
    required Future<List<VaultPhoto>> Function() listPhotos,
    required ChatCryptoService crypto,
    required SettingsRepository settings,
    required String? Function() currentUid,
    required Future<bool> Function() networkAllowed,
    required Future<String?> Function() currentVaultId,
    Future<Directory> Function()? restoreRoot,
    Future<Directory> Function()? tempRoot,
    PhotoHashCache? hashCache,
    BackupCoordinator? coordinator,
  }) : _stores = stores,
       _photoRepository = photoRepository,
       _listPhotos = listPhotos,
       _crypto = crypto,
       _settings = settings,
       _currentUid = currentUid,
       _networkAllowed = networkAllowed,
       _currentVaultId = currentVaultId,
       _restoreRoot = restoreRoot,
       _tempRoot = tempRoot,
       _hashCache = hashCache,
       _coordinator = coordinator ?? BackupCoordinator.inProcess();

  final List<BackupBlobStore> _stores;
  final PhotoRepository _photoRepository;
  final Future<List<VaultPhoto>> Function() _listPhotos;
  final ChatCryptoService _crypto;
  final SettingsRepository _settings;
  final String? Function() _currentUid;
  final Future<bool> Function() _networkAllowed;
  final Future<String?> Function() _currentVaultId;
  final PhotoHashCache? _hashCache;
  final BackupCoordinator _coordinator;

  /// Null means "use the vault root for the current mirror setting".
  final Future<Directory> Function()? _restoreRoot;

  /// Null means the platform temp directory.
  final Future<Directory> Function()? _tempRoot;

  static const _manifestSuffix = 'manifest.bin';
  static const _photoInfix = 'photo_';
  static const _thumbInfix = 'thumb_';
  static const _manifestVersion = 3;

  /// How often an automatic photo backup is due on app open (desktop path).
  static const backupInterval = Duration(hours: 24);

  Future<Directory> _root() async {
    final custom = _restoreRoot;
    if (custom != null) return custom();
    final mirror = await _settings.isExternalStorageMirrorEnabled();
    final vaultId = await _currentVaultId();
    if (vaultId == null) throw StateError('No vault to restore into.');
    return resolveVaultRoot(useExternalMirror: mirror, vaultId: vaultId);
  }

  /// Stable, non-reversible prefix for one account and vault.
  String? _prefix(String vaultId) {
    final accountPrefix = _legacyPrefix();
    if (accountPrefix == null) return null;
    final vaultHash = hash.sha256
        .convert(utf8.encode(vaultId))
        .toString()
        .substring(0, 20);
    return '$accountPrefix${vaultHash}_';
  }

  /// Prefix used by backups written before photo backups were vault-scoped.
  String? _legacyPrefix() {
    final uid = _currentUid();
    if (uid == null || uid.isEmpty) return null;
    final id = hash.sha256
        .convert(utf8.encode(uid))
        .toString()
        .substring(0, 20);
    return 'vp_${id}_';
  }

  /// Device is always used; cloud only when enabled and the network allows.
  Future<List<BackupBlobStore>> _activeStores(
    Map<BackupBlobStore, String> skipped,
  ) async {
    final cloudOn = await _settings.isBackupCloudEnabled();
    final netOk = await _networkAllowed();
    final active = <BackupBlobStore>[];
    for (final store in _stores) {
      if (store.isCloud && !cloudOn) {
        skipped[store] = 'Cloud backup is off';
      } else if (store.requiresNetwork && !netOk) {
        skipped[store] = 'Waiting for Wi-Fi or network';
      } else {
        active.add(store);
      }
    }
    return active;
  }

  /// Backs up when the last photo backup is older than [minAge] or never ran.
  /// Called on app open so desktop, which has no nightly job, is covered too.
  /// Returns null when nothing was due.
  Future<VaultPhotoBackupResult?> backupIfDue({
    Duration minAge = backupInterval,
    DateTime? now,
    DateTime? deadline,
  }) {
    return _coordinator.run(() async {
      if (_legacyPrefix() == null) return null;
      if (!await _settings.isBackupVaultPhotosEnabled()) return null;
      final vaultId = await _currentVaultId();
      if (vaultId == null) return null;
      final last = await _settings.getLastVaultPhotoBackupAt();
      final lastVaultId = await _settings.getLastVaultPhotoBackupVaultId();
      final current = now ?? DateTime.now();
      if (last != null &&
          lastVaultId == vaultId &&
          current.difference(last) < minAge) {
        return null;
      }
      return _backupUnlocked(deadline: deadline);
    });
  }

  /// Backs up every photo in the vault. Serialised with other backup work.
  ///
  /// An empty vault is a no-op and never replaces an existing backup. A vault
  /// that is empty on a new install looks the same as one whose photos were
  /// all removed. To clear a backup on purpose, use Delete backup.
  Future<VaultPhotoBackupResult> backup({
    bool interactive = false,
    DateTime? deadline,
  }) {
    return _coordinator.run(
      () => _backupUnlocked(interactive: interactive, deadline: deadline),
    );
  }

  Future<VaultPhotoBackupResult> _backupUnlocked({
    bool interactive = false,
    DateTime? deadline,
  }) async {
    final vaultId = await _currentVaultId();
    if (vaultId == null) throw StateError('No vault to back up.');
    final prefix = _prefix(vaultId);
    if (prefix == null) throw StateError('Not signed in to chat.');

    final skippedByStore = <BackupBlobStore, String>{};
    final active = await _activeStores(skippedByStore);
    final photos = await _listPhotos();
    final savedTo = <String>{};
    Map<String, String> skippedLabels() => {
      for (final e in skippedByStore.entries) e.key.label: e.value,
    };

    if (photos.isEmpty) {
      return VaultPhotoBackupResult(
        photoCount: 0,
        missingCount: 0,
        savedTo: const [],
        skipped: skippedLabels(),
      );
    }

    await _hashCache?.load();
    backupProgress.begin('Backing up vault photos', total: photos.length);
    try {
      final present = <BackupBlobStore, Set<String>>{};
      for (final store in active) {
        try {
          present[store] = (await store.list(
            prefix,
            interactive: interactive,
          )).toSet();
        } catch (e) {
          skippedByStore[store] = e.toString();
        }
      }
      final stores = present.keys.toList();

      var done = 0;
      var missing = 0;
      var completed = true;
      final backed = <VaultPhoto>[];
      final hashes = <String, (String, String)>{};
      for (final photo in photos) {
        if (deadline != null && DateTime.now().isAfter(deadline)) {
          completed = false;
          break;
        }
        backupProgress.update(++done);
        // A photo whose files are missing is reported and left out of the
        // manifest, not counted as saved.
        final photoHash = await _hashPhoto(
          '$vaultId:${photo.id}:photo',
          photo.encryptedFilePath,
        );
        final thumbHash = await _hashPhoto(
          '$vaultId:${photo.id}:thumb',
          photo.thumbnailPath,
        );
        if (photoHash == null || thumbHash == null) {
          missing++;
          continue;
        }
        backed.add(photo);
        hashes[photo.id] = (photoHash, thumbHash);

        final photoName = _blobName(prefix, _photoInfix, photo.id);
        final thumbName = _blobName(prefix, _thumbInfix, photo.id);
        for (final store in stores) {
          final have = present[store]!;
          if (have.contains(photoName) && have.contains(thumbName)) continue;
          try {
            await store.writeFile(
              photoName,
              File(photo.encryptedFilePath),
              interactive: interactive,
            );
            await store.writeFile(
              thumbName,
              File(photo.thumbnailPath),
              interactive: interactive,
            );
            have
              ..add(photoName)
              ..add(thumbName);
            savedTo.add(store.label);
          } catch (e) {
            skippedByStore[store] = e.toString();
          }
        }
      }

      if (!completed) {
        // Stopped early: the old manifest stays valid, and nothing is deleted,
        // because photos not reached yet are still in the vault.
        return VaultPhotoBackupResult(
          photoCount: backed.length,
          missingCount: missing,
          savedTo: savedTo.toList(),
          skipped: skippedLabels(),
          completed: false,
        );
      }

      final manifest = await _encodeManifest(vaultId, backed, hashes);
      final manifestFile = await _tempFile('manifest');
      try {
        await manifestFile.writeAsBytes(manifest, flush: true);
        for (final store in stores) {
          await store.writeFile(
            '$prefix$_manifestSuffix',
            manifestFile,
            interactive: interactive,
          );
          savedTo.add(store.label);
        }
      } finally {
        await _deleteQuietly(manifestFile);
      }
      // Drop blobs only for photos that left the vault (e.g. trashed). A photo
      // whose local file is missing keeps its backup.
      final live = {for (final photo in photos) photo.id};
      for (final store in stores) {
        for (final name in present[store]!) {
          if (!_isStaleBlob(prefix, name, live)) continue;
          await store.delete(name, interactive: interactive);
        }
      }

      await _settings.setLastVaultPhotoBackupAt(DateTime.now());
      await _settings.setLastVaultPhotoBackupVaultId(vaultId);
      return VaultPhotoBackupResult(
        photoCount: backed.length,
        missingCount: missing,
        savedTo: savedTo.toList(),
        skipped: skippedLabels(),
      );
    } finally {
      backupProgress.end();
      await _hashCache?.save();
    }
  }

  /// Restores photos from the first store that has the manifest (device
  /// first, then Drive). Photos already in the vault are left untouched.
  ///
  /// Throws [VaultPhotoBackupMismatch] if the backup belongs to another vault
  /// or was encrypted with a different account key.
  Future<VaultPhotoRestoreResult> restore({bool interactive = false}) {
    return _coordinator.run(() => _restoreUnlocked(interactive: interactive));
  }

  Future<VaultPhotoRestoreResult> _restoreUnlocked({
    bool interactive = false,
  }) async {
    final vaultId = await _currentVaultId();
    if (vaultId == null) throw StateError('No vault to restore into.');
    final prefix = _prefix(vaultId);
    final legacyPrefix = _legacyPrefix();
    if (prefix == null || legacyPrefix == null) {
      throw StateError('Not signed in to chat.');
    }
    const none = VaultPhotoRestoreResult(
      restored: 0,
      alreadyPresent: 0,
      unavailable: 0,
    );
    if (!await _settings.isBackupVaultPhotosEnabled()) return none;

    final failures = <String>{};
    final manifestFile = await _tempFile('manifest_read');
    try {
      final found = await _readFirstToFile(
        '$prefix$_manifestSuffix',
        manifestFile,
        interactive: interactive,
        failures: failures,
        fallbackNames: ['$legacyPrefix$_manifestSuffix'],
      );
      if (!found) {
        if (failures.isNotEmpty) {
          throw VaultPhotoBackupReadException(failures.toList());
        }
        return none;
      }

      final Uint8List plain;
      try {
        plain = await _crypto.decryptBackup(await manifestFile.readAsBytes());
      } catch (_) {
        throw const VaultPhotoBackupMismatch(
          'This backup cannot be decrypted. It may belong to a different '
          'account or be damaged.',
        );
      }
      final entries = await _decodeManifest(plain, vaultId);

      final root = await _root();
      final objectsDir = Directory(p.join(root.path, 'objects'));
      final thumbsDir = Directory(p.join(root.path, 'thumbs'));
      await objectsDir.create(recursive: true);
      await thumbsDir.create(recursive: true);

      var restored = 0;
      var alreadyPresent = 0;
      var unavailable = 0;
      backupProgress.begin('Restoring vault photos', total: entries.length);
      try {
        var done = 0;
        for (final (photo, photoHash, thumbHash) in entries) {
          backupProgress.update(++done);
          final existing = await _photoRepository.getPhotoById(photo.id);
          final existingPhotoValid =
              existing != null &&
              await _fileMatchesHash(existing.encryptedFilePath, photoHash);
          final existingThumbValid =
              existing != null &&
              await _fileMatchesHash(existing.thumbnailPath, thumbHash);
          if (existingPhotoValid && existingThumbValid) {
            alreadyPresent++;
            continue;
          }
          final photoPath = existingPhotoValid
              ? existing.encryptedFilePath
              : p.join(objectsDir.path, '${photo.id}_photo.enc');
          final thumbPath = existingThumbValid
              ? existing.thumbnailPath
              : p.join(thumbsDir.path, '${photo.id}_thumb.enc');
          final photoOk =
              existingPhotoValid ||
              await _restoreVerified(
                _blobName(prefix, _photoInfix, photo.id),
                photoHash,
                File(photoPath),
                interactive: interactive,
                failures: failures,
                fallbackNames: [_blobName(legacyPrefix, _photoInfix, photo.id)],
              );
          final thumbOk =
              existingThumbValid ||
              await _restoreVerified(
                _blobName(prefix, _thumbInfix, photo.id),
                thumbHash,
                File(thumbPath),
                interactive: interactive,
                failures: failures,
                fallbackNames: [_blobName(legacyPrefix, _thumbInfix, photo.id)],
              );
          if (!photoOk || !thumbOk) {
            if (photoOk && !existingPhotoValid) {
              await _deleteQuietly(File(photoPath));
            }
            if (thumbOk && !existingThumbValid) {
              await _deleteQuietly(File(thumbPath));
            }
            unavailable++;
            continue;
          }
          await _photoRepository.upsertPhoto(
            (existing ?? photo).copyWithPaths(
              encryptedFilePath: photoPath,
              thumbnailPath: thumbPath,
            ),
          );
          restored++;
        }
      } finally {
        backupProgress.end();
      }
      return VaultPhotoRestoreResult(
        restored: restored,
        alreadyPresent: alreadyPresent,
        unavailable: unavailable,
        foundBackup: true,
        failures: failures.toList(),
      );
    } finally {
      await _deleteQuietly(manifestFile);
    }
  }

  /// Removes this account's vault photo backup from the chosen stores.
  Future<void> deleteBackup({required bool device, required bool cloud}) {
    return _coordinator.run(() async {
      final vaultId = await _currentVaultId();
      if (vaultId == null) throw StateError('No vault to delete backup for.');
      final prefix = _prefix(vaultId);
      final legacyPrefix = _legacyPrefix();
      if (prefix == null || legacyPrefix == null) {
        throw StateError('Not signed in to chat.');
      }
      for (final store in _stores) {
        if (store.isCloud ? !cloud : !device) continue;
        for (final name in await store.list(prefix, interactive: true)) {
          await store.delete(name, interactive: true);
        }
        if (await _legacyManifestBelongsToVault(store, legacyPrefix, vaultId)) {
          for (final name in await store.list(
            legacyPrefix,
            interactive: true,
          )) {
            await store.delete(name, interactive: true);
          }
        }
      }
    });
  }

  Future<bool> _legacyManifestBelongsToVault(
    BackupBlobStore store,
    String prefix,
    String vaultId,
  ) async {
    final manifest = await _tempFile('legacy_manifest');
    try {
      final found = await store.readToFile(
        '$prefix$_manifestSuffix',
        manifest,
        interactive: true,
      );
      if (!found) return false;
      final plain = await _crypto.decryptBackup(await manifest.readAsBytes());
      await _decodeManifest(plain, vaultId);
      return true;
    } on VaultPhotoBackupMismatch {
      return false;
    } finally {
      await _deleteQuietly(manifest);
    }
  }

  // ---------------------------------------------------------------------------

  static String _blobName(String prefix, String infix, String photoId) =>
      '$prefix$infix$photoId.bin';

  static bool _isStaleBlob(String prefix, String name, Set<String> live) {
    if (name.endsWith(_manifestSuffix)) return false;
    final rest = name.substring(prefix.length);
    final infix = rest.startsWith(_photoInfix)
        ? _photoInfix
        : rest.startsWith(_thumbInfix)
        ? _thumbInfix
        : null;
    if (infix == null || !name.endsWith('.bin')) return false;
    final id = rest.substring(infix.length, rest.length - '.bin'.length);
    return !live.contains(id);
  }

  /// A scratch file in the temp directory for staging blobs.
  Future<File> _tempFile(String label) async {
    final dir = await (_tempRoot?.call() ?? getTemporaryDirectory());
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return File(p.join(dir.path, 'vault_backup_${label}_$stamp.tmp'));
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Scratch space only; the OS clears temp storage.
    }
  }

  /// Copies the blob into a scratch file, accepts it only if its SHA-256
  /// matches the manifest, then moves it into place. A corrupt copy in one
  /// store falls through to the next store.
  Future<bool> _restoreVerified(
    String name,
    String expectedSha256,
    File destination, {
    bool interactive = false,
    required Set<String> failures,
    List<String> fallbackNames = const [],
  }) async {
    final scratch = await _tempFile('blob');
    try {
      final found = await _readFirstToFile(
        name,
        scratch,
        interactive: interactive,
        expectedSha256: expectedSha256,
        failures: failures,
        fallbackNames: fallbackNames,
      );
      if (!found) return false;
      await destination.parent.create(recursive: true);
      if (await destination.exists()) await destination.delete();
      await scratch.rename(destination.path);
      return true;
    } finally {
      await _deleteQuietly(scratch);
    }
  }

  Future<bool> _fileMatchesHash(String path, String expectedSha256) async {
    try {
      final file = File(path);
      return await file.exists() && await _hashFile(file) == expectedSha256;
    } on FileSystemException {
      return false;
    }
  }

  /// Copies the first valid copy of [name] from the allowed stores into
  /// [destination]. When [expectedSha256] is given, a copy whose hash differs
  /// is skipped and the next store is tried. Returns false if none qualifies.
  Future<bool> _readFirstToFile(
    String name,
    File destination, {
    bool interactive = false,
    String? expectedSha256,
    Set<String>? failures,
    List<String> fallbackNames = const [],
  }) async {
    final cloudOn = await _settings.isBackupCloudEnabled();
    for (final candidate in [name, ...fallbackNames]) {
      for (final store in _stores) {
        if (store.isCloud && !cloudOn) continue;
        try {
          final ok = await store.readToFile(
            candidate,
            destination,
            interactive: interactive,
          );
          if (!ok) continue;
          if (expectedSha256 == null ||
              await _hashFile(destination) == expectedSha256) {
            return true;
          }
        } catch (error) {
          failures?.add('${store.label}: $error');
        }
      }
    }
    return false;
  }

  /// SHA-256 of a photo file, through the cache when one is configured. Null
  /// when the file is missing.
  Future<String?> _hashPhoto(String key, String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final cache = _hashCache;
      return cache != null
          ? await cache.hashOf(key, file)
          : await _hashFile(file);
    } on FileSystemException {
      return null;
    }
  }

  static Future<String> _hashFile(File file) async {
    final digest = await hash.sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  Future<Uint8List> _encodeManifest(
    String vaultId,
    List<VaultPhoto> photos,
    Map<String, (String, String)> hashes,
  ) async {
    final json = jsonEncode({
      'v': _manifestVersion,
      'vaultId': vaultId,
      'photos': [
        for (final photo in photos)
          {
            ..._photoToJson(photo),
            'photoSha256': hashes[photo.id]!.$1,
            'thumbSha256': hashes[photo.id]!.$2,
          },
      ],
    });
    return _crypto.encryptBackup(utf8.encode(json));
  }

  Future<List<(VaultPhoto, String, String)>> _decodeManifest(
    Uint8List plain,
    String currentVaultId,
  ) async {
    final map = jsonDecode(utf8.decode(plain));
    if (map is! Map || map['v'] != _manifestVersion || map['photos'] is! List) {
      throw const FormatException('Unsupported vault photo backup.');
    }
    if (map['vaultId'] != currentVaultId) {
      throw const VaultPhotoBackupMismatch(
        'This backup belongs to a different vault. Restore it from the vault '
        'it was made for.',
      );
    }
    return [
      for (final item in map['photos'] as List)
        () {
          final json = Map<String, dynamic>.from(item as Map);
          return (
            _photoFromJson(json),
            json['photoSha256'] as String,
            json['thumbSha256'] as String,
          );
        }(),
    ];
  }

  static Map<String, dynamic> _photoToJson(VaultPhoto photo) => {
    'id': photo.id,
    'originalFilename': photo.originalFilename,
    'wrappedDek': photo.wrappedDek,
    'photoNonce': photo.photoNonce,
    'thumbnailNonce': photo.thumbnailNonce,
    'encryptionVersion': photo.encryptionVersion,
    'checksumSha256': photo.checksumSha256,
    'fileSize': photo.fileSize,
    'mimeType': photo.mimeType,
    'createdTimeMs': photo.createdTimeMs,
    'importedTimeMs': photo.importedTimeMs,
    'modifiedTimeMs': photo.modifiedTimeMs,
    'favorite': photo.favorite,
    'albumId': photo.albumId,
  };

  static VaultPhoto _photoFromJson(Map<String, dynamic> json) => VaultPhoto(
    id: json['id'] as String,
    originalFilename: json['originalFilename'] as String,
    // Replaced with this device's paths on restore.
    encryptedFilePath: '',
    thumbnailPath: '',
    wrappedDek: json['wrappedDek'] as String,
    photoNonce: json['photoNonce'] as String,
    thumbnailNonce: json['thumbnailNonce'] as String,
    encryptionVersion: json['encryptionVersion'] as int,
    checksumSha256: json['checksumSha256'] as String,
    fileSize: json['fileSize'] as int,
    mimeType: json['mimeType'] as String,
    createdTimeMs: json['createdTimeMs'] as int,
    importedTimeMs: json['importedTimeMs'] as int,
    modifiedTimeMs: json['modifiedTimeMs'] as int,
    favorite: json['favorite'] as bool,
    isTrashed: false,
    albumId: json['albumId'] as String?,
  );
}
