# Drift ORM Integration Guide - Critical for Photo Persistence

## Overview

The Drift ORM is now partially integrated. You have:
- ✅ Full Drift database definition (`vault_database.dart`)
- ✅ All table definitions with proper columns and indexes
- ✅ High-level query methods
- ✅ Drift + build_runner already in pubspec.yaml
- ❌ Generated Drift files (not yet created)
- ❌ PersistentPhotoRepository wired to use Drift (still placeholder)

This guide walks through completing the integration so encrypted photos persist across app restarts.

---

## Step 1: Generate Drift Database Classes

Run the build_runner to generate TypeScript-safe database accessors:

```bash
flutter pub run build_runner build
```

**Expected output:**
```
[INFO] Building new asset graph completed, took 1.2s
[INFO] Running build
[INFO] GeneratingBuildScriptAsync : drift|build
[INFO] GeneratingAsync : drift:drift
[INFO] 1.2s elapsed
[INFO] ..................... 54.5s total
```

**Files generated:**
```
lib/storage/local_db/vault_database.g.dart  ← AUTO-GENERATED (do not edit)
```

**If build fails:**
- Clear build artifacts: `flutter clean && flutter pub get`
- Try again: `flutter pub run build_runner build --delete-conflicting-outputs`
- Check that all imports in `vault_database.dart` are correct (see Step 0)

---

## Step 2: Wire PersistentPhotoRepository to Use Drift

### Update `persistent_photo_repository.dart`

Replace the placeholder repository with actual Drift queries:

```dart
import 'package:uuid/uuid.dart';
import '../../storage/local_db/vault_database.dart';
import '../../domain/entities/vault_photo.dart';

abstract class PersistentPhotoRepository {
  Future<void> initialize();
  Future<void> close();
  Future<VaultPhoto?> getPhotoById(String id);
  Future<List<VaultPhoto>> listPhotos({
    int limit = 50,
    int offset = 0,
    bool includeTrashed = false,
  });
  Future<bool> existsChecksum(String checksum);
  Future<void> savePhoto(VaultPhoto photo);
  Future<void> updatePhoto(VaultPhoto photo);
  Future<void> moveToTrash(String photoId, int expiresAtMs);
  Future<void> restoreFromTrash(String photoId);
  Future<void> permanentlyDelete(String photoId);
  Future<List<VaultPhoto>> getExpiredTrash(int nowMs);
  Future<int> countPhotos({bool includeTrashed = false});
}

class PersistentPhotoRepositoryImpl implements PersistentPhotoRepository {
  late VaultDatabase _db;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _db = VaultDatabase();
    _initialized = true;
  }

  @override
  Future<void> close() async {
    if (!_initialized) return;
    await _db.close();
    _initialized = false;
  }

  @override
  Future<VaultPhoto?> getPhotoById(String id) async {
    _ensureInitialized();
    return _db.getPhotoById(id);
  }

  @override
  Future<List<VaultPhoto>> listPhotos({
    int limit = 50,
    int offset = 0,
    bool includeTrashed = false,
  }) async {
    _ensureInitialized();
    if (includeTrashed) {
      return (select(_db.photos)
              ..limit(limit, offset: offset)
              ..orderBy([(p) => OrderingTerm(
                    expression: p.importedTimeMs,
                    mode: OrderingMode.desc,
                  )]))
          .get();
    }
    return _db.getGalleryPhotos();
  }

  @override
  Future<bool> existsChecksum(String checksum) async {
    _ensureInitialized();
    return _db.photoWithChecksumExists(checksum);
  }

  @override
  Future<void> savePhoto(VaultPhoto photo) async {
    _ensureInitialized();
    await _db.insertPhoto(photo);
  }

  @override
  Future<void> updatePhoto(VaultPhoto photo) async {
    _ensureInitialized();
    await _db.updatePhoto(photo);
  }

  @override
  Future<void> moveToTrash(String photoId, int expiresAtMs) async {
    _ensureInitialized();
    await _db.movePhotoToTrash(photoId, expiresAtMs);
  }

  @override
  Future<void> restoreFromTrash(String photoId) async {
    _ensureInitialized();
    await _db.restorePhotoFromTrash(photoId);
  }

  @override
  Future<void> permanentlyDelete(String photoId) async {
    _ensureInitialized();
    await _db.permanentlyDeletePhoto(photoId);
  }

  @override
  Future<List<VaultPhoto>> getExpiredTrash(int nowMs) async {
    _ensureInitialized();
    return _db.getExpiredTrashPhotos(nowMs);
  }

  @override
  Future<int> countPhotos({bool includeTrashed = false}) async {
    _ensureInitialized();
    return _db.countPhotos(includeTrashed: includeTrashed);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('PersistentPhotoRepository not initialized. Call initialize() first.');
    }
  }
}
```

---

## Step 3: Update VaultApp to Initialize Photo Repository

Update `lib/presentation/app/vault_app.dart`:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  
  // Initialize persistent photo repository
  _initializePhotoRepository();
  
  _createVaultUseCase = CreateVaultUseCase(
    // ... rest of setup
  );
  // ... rest of initState
}

Future<void> _initializePhotoRepository() async {
  try {
    await _photoRepository.initialize();
  } catch (e) {
    debugPrint('Failed to initialize photo repository: $e');
  }
}

@override
void dispose() {
  _onboardingCubit.close();
  _shareStreamSub?.cancel();
  _backgroundLockTimer?.cancel();
  _vaultSession.lock();
  WidgetsBinding.instance.removeObserver(this);
  _sessionUnlocked.dispose();
  
  // Close photo repository (cleanup database connection)
  _photoRepository.close();
  
  super.dispose();
}
```

---

## Step 4: Update ImportManager to Persist Metadata

The ImportManager already writes encrypted files. Now it must also persist metadata to the database:

**In `import_manager.dart`, update the `enqueueImport()` method:**

```dart
// After DEK wrapping and file write, add:
await _photoRepository.savePhoto(
  VaultPhoto(
    id: photoId,
    originalFilename: photo.displayName ?? 'photo',
    createdTimeMs: photo.modifiedDate?.millisecondsSinceEpoch ?? nowMs,
    importedTimeMs: nowMs,
    modifiedTimeMs: nowMs,
    source: 'gallery', // or 'camera', 'file_picker', etc.
    albumId: null,
    favorite: 0,
    encryptedFilePath: photoFilePath,
    thumbnailPath: thumbnailPath,
    thumbnailNonce: base64Encode(thumbnailNonce),
    photoNonce: base64Encode(photoNonce),
    wrappedDek: jsonEncode(wrappedKey.toJson()), // If WrappedKey has toJson()
    encryptionVersion: 1,
    syncStatus: 'local',
    backupStatus: 'not_backed_up',
    checksumSha256: checksum,
    fileSize: photoBytes.length,
    mimeType: photo.mimeType ?? 'image/jpeg',
    isTrashed: 0,
    trashExpiresAtMs: null,
    deletedTombstoneAtMs: null,
  ),
);
```

---

## Step 5: Test End-to-End Persistence

### Manual Test

1. **Start app (fresh state):**
   ```bash
   flutter run
   ```

2. **Complete onboarding:**
   - Create vault with PIN
   - Enable biometric (optional)
   - App shows empty gallery

3. **Import photos:**
   - Tap Import
   - Select 3-5 photos from gallery/camera
   - Confirm import
   - Wait for encryption to complete
   - Verify thumbnails appear in gallery

4. **Close app completely:**
   - Press home button
   - Swipe app out of recents (kill process)
   - OR: `adb shell am force-stop com.example.photo_vault`

5. **Reopen app:**
   - Tap app icon
   - App lock screen appears
   - Unlock with PIN or biometric

6. **Verify persistence:**
   - Gallery should show same photos as before
   - Thumbnails should decrypt and display
   - NO photos should be missing
   - NO errors in console

### What Success Looks Like
```
I/flutter: App started
I/flutter: PersistentPhotoRepository initialized
I/flutter: Gallery queries database...
I/flutter: 5 photos loaded
I/flutter: Thumbnails decrypting...
I/flutter: Gallery displaying
```

### Troubleshooting

| Issue | Solution |
|-------|----------|
| Build fails on `flutter pub run build_runner` | Run `flutter clean && flutter pub get` then try again |
| `Database locked` error | Close app completely, wait 5s, reopen |
| Photos still disappear on restart | Check if `_photoRepository.close()` called in dispose |
| Thumbnails not showing | Verify encrypted thumbnail files still exist at `/data/data/.../files/vault/objects/` |
| App crashes on unlock | Check that `_db.get_galleryPhotos()` doesn't have null pointer errors |

---

## Step 6: Automated Tests

Add tests to verify persistence across simulated app restarts:

**File: `test/integration/photo_persistence_test.dart`** (NEW)

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/vault_session.dart';
import 'package:photo_vault/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/data/repositories_impl/persistent_photo_repository.dart';
import 'package:photo_vault/domain/entities/vault_photo.dart';

void main() {
  group('Photo Persistence Across App Restarts', () {
    late PersistentPhotoRepository repository;
    late VaultSession vaultSession;

    setUp(() async {
      repository = PersistentPhotoRepositoryImpl();
      vaultSession = VaultSession();
      await repository.initialize();
    });

    tearDown(() async {
      await repository.close();
    });

    test('Photo metadata persists in database after app restart', () async {
      // Arrange
      final photoId = 'photo-test-1';
      const checksum = 'abc123def456';
      final now = DateTime.now().millisecondsSinceEpoch;

      final photo = VaultPhoto(
        id: photoId,
        originalFilename: 'test_photo.jpg',
        createdTimeMs: now,
        importedTimeMs: now,
        modifiedTimeMs: now,
        source: 'gallery',
        albumId: null,
        favorite: 0,
        encryptedFilePath: '/path/to/photo.enc',
        thumbnailPath: '/path/to/thumb.enc',
        thumbnailNonce: 'nonce123',
        photoNonce: 'nonce456',
        wrappedDek: '{"nonce":"x","ciphertext":"y"}',
        encryptionVersion: 1,
        syncStatus: 'local',
        backupStatus: 'not_backed_up',
        checksumSha256: checksum,
        fileSize: 5242880,
        mimeType: 'image/jpeg',
        isTrashed: 0,
        trashExpiresAtMs: null,
        deletedTombstoneAtMs: null,
      );

      // Act 1: Save photo
      await repository.savePhoto(photo);

      // Assert 1: Photo retrieved immediately
      var retrieved = await repository.getPhotoById(photoId);
      expect(retrieved, isNotNull);
      expect(retrieved!.originalFilename, equals('test_photo.jpg'));
      expect(retrieved.checksumSha256, equals(checksum));

      // Act 2: Close and re-open database (simulating app restart)
      await repository.close();
      await repository.initialize();

      // Assert 2: Photo still there after restart
      retrieved = await repository.getPhotoById(photoId);
      expect(retrieved, isNotNull, reason: 'Photo should persist after app restart');
      expect(retrieved!.originalFilename, equals('test_photo.jpg'));
      expect(retrieved.checksumSha256, equals(checksum));
    });

    test('Multiple photos persist in gallery listing', () async {
      // Arrange
      final now = DateTime.now().millisecondsSinceEpoch;
      final photos = List.generate(5, (i) {
        return VaultPhoto(
          id: 'photo-$i',
          originalFilename: 'photo_$i.jpg',
          createdTimeMs: now - (i * 1000),
          importedTimeMs: now,
          modifiedTimeMs: now,
          source: 'gallery',
          albumId: null,
          favorite: i % 2,
          encryptedFilePath: '/path/to/photo_$i.enc',
          thumbnailPath: '/path/to/thumb_$i.enc',
          thumbnailNonce: 'nonce_$i',
          photoNonce: 'nonce_photo_$i',
          wrappedDek: '{"nonce":"x","ciphertext":"y"}',
          encryptionVersion: 1,
          syncStatus: 'local',
          backupStatus: 'not_backed_up',
          checksumSha256: 'checksum_$i',
          fileSize: 1024 * (i + 1),
          mimeType: 'image/jpeg',
          isTrashed: 0,
          trashExpiresAtMs: null,
          deletedTombstoneAtMs: null,
        );
      });

      // Act 1: Save all photos
      for (final photo in photos) {
        await repository.savePhoto(photo);
      }

      // Assert 1: All photos listed
      var listing = await repository.listPhotos();
      expect(listing.length, equals(5));

      // Act 2: Simulate app restart
      await repository.close();
      await repository.initialize();

      // Assert 2: All photos still there
      listing = await repository.listPhotos();
      expect(listing.length, equals(5), reason: 'All photos should persist after restart');
    });

    test('Duplicate detection works across restarts', () async {
      // Arrange
      const checksum = 'duplicate-checksum-xyz';
      final now = DateTime.now().millisecondsSinceEpoch;

      final photo1 = VaultPhoto(
        id: 'photo-1',
        originalFilename: 'photo_1.jpg',
        createdTimeMs: now,
        importedTimeMs: now,
        modifiedTimeMs: now,
        source: 'gallery',
        albumId: null,
        favorite: 0,
        encryptedFilePath: '/path/to/photo1.enc',
        thumbnailPath: '/path/to/thumb1.enc',
        thumbnailNonce: 'nonce1',
        photoNonce: 'nonce_p1',
        wrappedDek: '{"nonce":"x","ciphertext":"y"}',
        encryptionVersion: 1,
        syncStatus: 'local',
        backupStatus: 'not_backed_up',
        checksumSha256: checksum,
        fileSize: 1024,
        mimeType: 'image/jpeg',
        isTrashed: 0,
        trashExpiresAtMs: null,
        deletedTombstoneAtMs: null,
      );

      // Act: Save photo and check
      await repository.savePhoto(photo1);
      var exists = await repository.existsChecksum(checksum);
      expect(exists, isTrue);

      // Simulate restart
      await repository.close();
      await repository.initialize();

      // Assert: Duplicate detection still works after restart
      exists = await repository.existsChecksum(checksum);
      expect(exists, isTrue, reason: 'Checksum should persist for duplicate detection');
    });
  });
}
```

**Run tests:**
```bash
flutter test test/integration/photo_persistence_test.dart
```

---

## Step 7: Verify No Breaking Changes

After Drift integration, verify all existing tests still pass:

```bash
flutter test --coverage
```

Expected: All tests pass (currently ~29)

---

## Checklist for MVP Completion

- [ ] Generated Drift database files (`vault_database.g.dart` exists)
- [ ] No build errors after `flutter pub run build_runner build`
- [ ] PersistentPhotoRepository properly implements all Drift queries
- [ ] VaultApp initializes and closes photo repository
- [ ] ImportManager saves metadata to database after file encryption
- [ ] Manual test: Import → Restart → Photos still there
- [ ] Auto test: `photo_persistence_test.dart` all pass
- [ ] Gallery queries database and displays photos correctly
- [ ] Thumbnails decrypt and cache work after restart
- [ ] Lock screen still works
- [ ] No plaintext photos on disk

---

## Next: After Persistence Works

Once this is complete and tests pass:

1. **Wire ImportPreviewScreen into router** — User can preview full photo before import
2. **Implement secure trash lifecycle** — Auto-delete after 30 days
3. **Add search/filter/sort** — Gallery queries for galleries > 100 photos
4. **Implement sensitive action re-auth** — Gate for PIN change, restore, export
5. **Add Google backup/sync** — Optional mode for off-device recovery

All built on top of this persistent foundation.
