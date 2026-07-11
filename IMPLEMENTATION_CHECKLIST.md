# DELIVERABLES & NEXT STEPS - Encrypted Photo Vault MVP

## 📋 What You've Received (Session Summary)

### Analysis Documents (3 files)
1. **STORAGE_ARCHITECTURE.md** — Complete explanation of Android storage paths, encryption layers, and data flow
2. **STORAGE_FAQ.md** — Direct answers to your 4 questions about photo retention, preview, restart behavior, and storage location
3. **PERSISTENCE_FIX_SUMMARY.md** — Technical details of what's broken and why

### Status Documents (2 files)
4. **IMPLEMENTATION_STATUS.md** — Detailed breakdown of what's implemented vs. what's TODO
5. **DRIFT_INTEGRATION_GUIDE.md** — Step-by-step instructions to complete photo persistence (critical blocker)

### Core Implementation Files
6. **vault_database.dart** — Complete Drift ORM database definition with all table schemas and query methods
7. **persistent_photo_repository.dart** — Interface and placeholder implementation (needs Drift wiring)
8. **import_preview_screen.dart** — Photo preview UI with zoom capability (created but not routed)

### Previous Implementations (from prior session)
- VaultSession: In-memory VMK storage with zero-clearing on lock
- ImportManager: Real AES-256-GCM encryption with per-photo DEK and wrapping
- App lock/unlock flow with PIN and biometric support
- Background auto-lock after 20 seconds
- Gallery with thumbnail decryption on-demand
- Security infrastructure (PBKDF2 KEK derivation, wrapped keys)

---

## ❌ Critical Blocker: Photo Persistence Across Restarts

### The Problem (Your Question #3)

**Current State:**
- Photos ARE encrypted and written to disk: `/data/data/com.example.photo_vault/files/vault/objects/{id}.photo.enc`
- Photo metadata IS NEVER saved to SQLite database
- On app restart, `InMemoryPhotoRepository` clears
- Gallery cannot find encrypted files → "No photos"
- Encrypted files orphaned on disk (inaccessible)

**Why it's happening:**
```
ImportManager writes encrypted file ✅
  ↓
InMemoryPhotoRepository stores metadata in RAM only ❌
  ↓
App closes (process killed)
  ↓
App reopens
  ↓
InMemoryPhotoRepository is empty (RAM cleared)
  ↓
Gallery queries empty repository
  ↓
"No photos" displayed (but files still on disk!) ❌
```

### The Solution: Drift ORM Integration

**What needs to happen:**
1. Generate Drift database files using build_runner
2. Implement PersistentPhotoRepository with actual SQLite queries
3. Save photo metadata when files are encrypted
4. Load metadata on app startup
5. Gallery queries database → finds encrypted files → decrypts and displays

---

## 🚀 IMMEDIATE ACTION REQUIRED (To Fix Photos Persistence)

### Execute These Steps (In Order):

#### **Step 1: Generate Drift Database Classes** ⚡ (5 minutes)

```bash
cd your-project-directory
flutter pub run build_runner build
```

**Expected:**
- File created: `lib/storage/local_db/vault_database.g.dart`
- No build errors
- Console output: `1.2s elapsed ... 54.5s total`

**If it fails:**
```bash
flutter clean && flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
```

---

#### **Step 2: Implement Photo Persistence Queries** ⚡ (30 minutes)

Edit: `lib/data/repositories_impl/persistent_photo_repository.dart`

Replace TODO placeholders with this implementation:

```dart
// At the top of the file, add these imports:
import 'package:drift/drift.dart' as drift show update, delete;
import '../../storage/local_db/vault_database.dart';

// Replace the entire PersistentPhotoRepositoryImpl class with:

class PersistentPhotoRepositoryImpl implements PersistentPhotoRepository {
  late VaultDatabase _db;
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      _db = VaultDatabase();
      _initialized = true;
    } catch (e) {
      throw Exception('Failed to initialize database: $e');
    }
  }

  @override
  Future<void> close() async {
    if (!_initialized) return;
    try {
      await _db.close();
      _initialized = false;
    } catch (e) {
      throw Exception('Failed to close database: $e');
    }
  }

  @override
  Future<VaultPhoto?> getPhotoById(String id) async {
    _checkInitialized();
    try {
      return await _db.getPhotoById(id);
    } catch (e) {
      throw Exception('Failed to get photo: $e');
    }
  }

  @override
  Future<List<VaultPhoto>> listPhotos({
    int limit = 50,
    int offset = 0,
    bool includeTrashed = false,
  }) async {
    _checkInitialized();
    try {
      if (includeTrashed) {
        return await (drift.select(_db.photos)
              ..limit(limit, offset: offset)
              ..orderBy([(p) => drift.OrderingTerm(
                    expression: p.importedTimeMs,
                    mode: drift.OrderingMode.desc,
                  )]))
            .get();
      }
      return await _db.getGalleryPhotos();
    } catch (e) {
      throw Exception('Failed to list photos: $e');
    }
  }

  @override
  Future<bool> existsChecksum(String checksum) async {
    _checkInitialized();
    try {
      return await _db.photoWithChecksumExists(checksum);
    } catch (e) {
      throw Exception('Failed to check checksum: $e');
    }
  }

  @override
  Future<void> savePhoto(VaultPhoto photo) async {
    _checkInitialized();
    try {
      await _db.insertPhoto(photo);
    } catch (e) {
      throw Exception('Failed to save photo: $e');
    }
  }

  @override
  Future<void> updatePhoto(VaultPhoto photo) async {
    _checkInitialized();
    try {
      await _db.updatePhoto(photo);
    } catch (e) {
      throw Exception('Failed to update photo: $e');
    }
  }

  @override
  Future<void> moveToTrash(String photoId, int expiresAtMs) async {
    _checkInitialized();
    try {
      await _db.movePhotoToTrash(photoId, expiresAtMs);
    } catch (e) {
      throw Exception('Failed to move to trash: $e');
    }
  }

  @override
  Future<void> restoreFromTrash(String photoId) async {
    _checkInitialized();
    try {
      await _db.restorePhotoFromTrash(photoId);
    } catch (e) {
      throw Exception('Failed to restore from trash: $e');
    }
  }

  @override
  Future<void> permanentlyDelete(String photoId) async {
    _checkInitialized();
    try {
      await _db.permanentlyDeletePhoto(photoId);
    } catch (e) {
      throw Exception('Failed to permanently delete photo: $e');
    }
  }

  @override
  Future<List<VaultPhoto>> getExpiredTrash(int nowMs) async {
    _checkInitialized();
    try {
      return await _db.getExpiredTrashPhotos(nowMs);
    } catch (e) {
      throw Exception('Failed to get expired trash: $e');
    }
  }

  void _checkInitialized() {
    if (!_initialized) {
      throw StateError(
        'PersistentPhotoRepository not initialized. Call initialize() first.',
      );
    }
  }
}
```

---

#### **Step 3: Wire Photo Repository Initialization** ⚡ (10 minutes)

Edit: `lib/presentation/app/vault_app.dart`

**Change line 19:**
```dart
// OLD:
import '../../data/repositories_impl/in_memory_photo_repository.dart';
// NEW:
import '../../data/repositories_impl/persistent_photo_repository.dart';
```

**Change line 74:**
```dart
// OLD:
final _photoRepository = InMemoryPhotoRepository();
// NEW:
late final PersistentPhotoRepository _photoRepository = PersistentPhotoRepositoryImpl();
```

**Add initialization (after `WidgetsBinding.instance.addObserver(this);` in initState):**
```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
  
  // Initialize persistent photo repository
  _initializePhotoRepository();
  
  // ... rest of setup
}

Future<void> _initializePhotoRepository() async {
  try {
    await _photoRepository.initialize();
  } catch (e) {
    debugPrint('Failed to initialize photo repository: $e');
  }
}
```

**Update dispose:**
```dart
@override
void dispose() {
  _onboardingCubit.close();
  _shareStreamSub?.cancel();
  _backgroundLockTimer?.cancel();
  _vaultSession.lock();
  WidgetsBinding.instance.removeObserver(this);
  _sessionUnlocked.dispose();
  
  // Close photo repository
  _photoRepository.close();
  
  super.dispose();
}
```

---

#### **Step 4: Update ImportManager to Persist Metadata** ⚡ (15 minutes)

Edit: `lib/application/services/import_manager.dart`

**Add this after the encrypted file is written (around line 160):**

```dart
// Save photo metadata to database
try {
  await _photoRepository.savePhoto(VaultPhoto(
    id: photoId,
    originalFilename: photo.displayName ?? 'photo',
    createdTimeMs: photo.modifiedDate?.millisecondsSinceEpoch ?? nowMs,
    importedTimeMs: nowMs,
    modifiedTimeMs: nowMs,
    source: source, // 'camera', 'gallery', etc.
    albumId: null,
    favorite: 0,
    encryptedFilePath: photoFilePath,
    thumbnailPath: thumbnailPath,
    thumbnailNonce: Base64Codec().encode(thumbnailNonce),
    photoNonce: Base64Codec().encode(photoNonce),
    wrappedDek: jsonEncode({
      'nonce': Base64Codec().encode(wrappedKey.nonce),
      'ciphertext': Base64Codec().encode(wrappedKey.ciphertext),
    }),
    encryptionVersion: 1,
    syncStatus: 'local',
    backupStatus: 'not_backed_up',
    checksumSha256: checksum,
    fileSize: photoBytes.length,
    mimeType: photo.mimeType ?? 'image/jpeg',
    isTrashed: 0,
    trashExpiresAtMs: null,
    deletedTombstoneAtMs: null,
  ));
} catch (e) {
  debugPrint('Failed to save photo metadata: $e');
  // Still return success (file is encrypted), but log the error
}
```

---

#### **Step 5: Test the Fix** ⚡ (10 minutes)

1. **Run the app:**
   ```bash
   flutter run
   ```

2. **Create vault and import 3 photos**
   - Complete onboarding
   - Import photos from gallery
   - Verify thumbnails appear in gallery

3. **Close app completely:**
   ```bash
   # Kill the app process (long-press home, swipe out)
   # OR from terminal:
   adb shell am force-stop com.example.photo_vault
   ```

4. **Reopen app:**
   - Tap app icon
   - Unlock with PIN
   - **✅ Photos should still be there!**
   - Thumbnails should decrypt and display

5. **Verify success:**
   - No "No photos" message
   - Same photos appear
   - Thumbnails show correctly
   - Console shows no errors

---

#### **Step 6: Run Tests** ⚡ (5 minutes)

```bash
flutter test
```

**Expected:** All tests pass (29 total)

If any fail, check:
- Did you import PersistentPhotoRepository correctly?
- Did you add await to _photoRepository.initialize()?
- Are all Drift-generated files present?

---

## 📊 After Drift Integration Complete

Once photos persist correctly, you'll be ready to:

### Phase 2: Gallery Enhancements
- [ ] Wire import preview screen (show full photo before encrypt)
- [ ] Add search/filter/sort
- [ ] Implement trash lifecycle (30-day auto-delete)
- [ ] Add favorites management
- [ ] Add albums/tags system

### Phase 3: Backup & Sync
- [ ] Firebase Auth integration
- [ ] Google Drive VMK backup
- [ ] Optional photo sync
- [ ] Restore after reinstall
- [ ] Incremental sync

### Phase 4: Sharing & Security
- [ ] Encrypted export packages
- [ ] Guarded decrypted export (re-auth required)
- [ ] Sensitive action re-authentication gates
- [ ] Security event logging

---

## 📈 Architecture After Drift Integration

```
┌─────────────────────────────────────────────────┐
│  Gallery UI                                      │
│  (shows thumbnails, user browsing)              │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  Gallery Repository (PersistentPhotoRepositoryImpl)
│  - listPhotos()  [queries SQLite]               │
│  - getPhotoById()                                │
│  - savePhoto()   [on import, persists]          │
│  - moveToTrash()                                 │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  Drift Database (VaultDatabase)                  │
│  - Typed SQLite queries                          │
│  - Table: Photos (with metadata)                 │
│  - Table: Trash, Tags, Albums, etc.             │
└──────────────────┬──────────────────────────────┘
                   │
┌──────────────────▼──────────────────────────────┐
│  SQLite Database File                            │
│  /data/data/.../databases/vault.db              │
│  (PERSISTENT - survives app restart)            │
└─────────────────────────────────────────────────┘
                   
┌─────────────────────────────────────────────────┐
│  Encrypted Files (App-Private Storage)          │
│  /data/data/.../files/vault/objects/            │
│  ├── photo-123.photo.enc                        │
│  ├── photo-123.thumb.enc                        │
│  └── photo-456.photo.enc                        │
│  (PERSISTENT - survives app restart)            │
└─────────────────────────────────────────────────┘
```

---

## 🎯 Success Criteria

**Photo persistence is working when:**

| Check | Status |
|-------|--------|
| Import 5 photos successfully | ✅ |
| Close app completely | ✅ |
| Reopen app | ✅ |
| Unlock vault | ✅ |
| Gallery shows same 5 photos | ✅ (THIS IS THE FIX) |
| Thumbnails decrypt and display | ✅ |
| No errors in console | ✅ |
| All tests pass | ✅ |

---

## 📞 Troubleshooting Quick Reference

| Problem | Solution |
|---------|----------|
| `import 'vault_database.g.dart'` error after build_runner | Run: `flutter clean && flutter pub get && flutter pub run build_runner build` |
| Database still locked | Kill app, wait 5s, reopen |
| Photos still disappear | Verify `_photoRepository.close()` called in dispose() |
| `StateError: not initialized` | Verify `initialize()` called in VaultApp.initState() |
| Encryption fails | Check that `_photoRepository.savePhoto()` is after file write |
| Test failures | Check that all test setUp() has VaultSession() injected |

---

## 📚 Files to Review

**Critical (must implement):**
1. `lib/storage/local_db/vault_database.dart` — Drift database definition (NEW)
2. `lib/data/repositories_impl/persistent_photo_repository.dart` — Photo queries (UPDATED)
3. `lib/presentation/app/vault_app.dart` — Initialization wiring (UPDATED)

**Reference:**
- `DRIFT_INTEGRATION_GUIDE.md` — Full step-by-step guide
- `STORAGE_FAQ.md` — Answers to your storage questions
- `STORAGE_ARCHITECTURE.md` — How Android storage works

**For Testing:**
- Run: `flutter test`
- Expected: All 29 tests pass after steps 1-4

---

## ⏱️ Time Estimate

- Step 1 (generate Drift): 5 min
- Step 2 (implement queries): 30 min
- Step 3 (wire initialization): 10 min
- Step 4 (update ImportManager): 15 min
- Step 5 (manual testing): 10 min
- Step 6 (run tests): 5 min

**Total: ~75 minutes (1.5 hours)**

Once complete, photos will persist across app restarts and you can move on to gallery enhancements, backup/sync, and sharing features.

---

**Next: Follow the immediate action steps above. Start with Step 1 (build_runner). Ask if you hit any issues!**
