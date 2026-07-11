# Answers to Your Storage Questions

## Question 1: When we encrypt the photos, those are not retained on disk on Android.

**FALSE** — The encrypted photos ARE retained on disk. But the metadata is NOT retained.

**What's happening:**
1. ✅ Photo is encrypted with AES-256-GCM + DEK
2. ✅ Encrypted bytes written to disk at:
   ```
   /data/data/com.example.photo_vault/files/vault/objects/{photoId}.photo.enc
   ```
3. ✅ Encrypted thumbnail written to:
   ```
   /data/data/com.example.photo_vault/files/vault/objects/{photoId}.thumb.enc
   ```
4. ❌ Photo metadata is NEVER written to SQLite database
5. ❌ On app restart, gallery has no way to know encrypted files exist

**Why encrypted files stay on disk:**
- App-private storage (`/data/data/.../files/`) is permanent
- Files only deleted if app is uninstalled or user manually clears app data
- Encrypted bytes are just data; they'll sit there forever

**Why metadata is lost:**
- `InMemoryPhotoRepository` only stores in RAM
- RAM cleared when app process exits
- No database query implementation → no persistent metadata

---

## Question 2: There is an option to preview the selected photo.

**PARTIALLY TRUE** — The screen exists but is not wired into the import flow.

**What exists:**
- ✅ `lib/presentation/screens/import/import_preview_screen.dart`
- ✅ Shows full-screen photo with zoom capability
- ✅ Displays file name, size, and metadata
- ✅ Allows user to inspect before importing

**What's missing:**
- ❌ Route not registered in GoRouter
- ❌ Import review screen doesn't navigate to preview
- ❌ User must tap photo in list → currently no action bound

**How to enable:**
1. Add route to `vault_app.dart`:
   ```dart
   GoRoute(
     path: 'import/preview/:photoId',
     builder: (context, state) => ImportPreviewScreen(
       photoId: state.pathParameters['photoId']!,
     ),
   ),
   ```
2. Update `import_review_screen.dart` to navigate on photo tap:
   ```dart
   onTap: () => context.push('/import/preview/${photo.id}')
   ```

---

## Question 3: When app is reopened, the encrypted photos are gone.

**TECHNICALLY INCORRECT** — The encrypted photos are still there on disk, but the app can't find them.

**What's really happening:**
1. ✅ Encrypted photo files still exist at `/data/data/.../files/vault/objects/`
2. ❌ Gallery re-opens → queries `InMemoryPhotoRepository`
3. ❌ In-memory map is empty → no photo records loaded
4. ❌ ImportManager sees no metadata → assumes no photos exist
5. ✅ Encrypted files orphaned on disk (inaccessible to gallery)

**The encrypted files are not gone:**
- They're just invisible to the app's gallery UI
- If someone extracted the database and encrypted files from the device, they could potentially recover them with the VMK
- But from the app's perspective, they're "gone" because metadata is missing

**This will be fixed when we:**
1. Implement Drift database integration
2. Save photo metadata to SQLite on import
3. Load photo metadata from SQLite on app startup
4. Gallery queries database → finds encrypted files → decrypts and displays

---

## Question 4: Where are these photos stored on Android?

### Photos Stored at:
```
/data/data/com.example.photo_vault/files/vault/objects/
├── {photoId}.photo.enc       ← AES-256-GCM encrypted full photo
├── {photoId}.thumb.enc       ← AES-256-GCM encrypted thumbnail
├── {photoId}.photo.enc       ← (repeat for each imported photo)
└── {photoId}.thumb.enc
```

**Why this path:**
- App-private storage: other apps can't access without root
- Survives app restart
- Deleted only if app uninstalled or data cleared

### Metadata Stored at (not yet implemented):
```
/data/data/com.example.photo_vault/databases/vault.db
└── photos table (currently EMPTY — no Drift integration yet)
```

### VMK Wrapped Key Stored at:
```
Android Keystore (via flutter_secure_storage)
└── Hardware-backed when available (Trusted Execution Environment)
```

---

## The Complete Data Flow

### On Import (Today's State):
```
User selects photo
  ↓
ImportManager receives plaintext bytes
  ↓
✅ Calculate SHA256 checksum
✅ Generate random DEK (Data Encryption Key)
✅ Encrypt photo with AES-256-GCM (DEK)
✅ Wrap DEK with AES-256-GCM (VMK)
✅ Write encrypted file to /data/data/.../files/vault/objects/{photoId}.photo.enc
✅ Create metadata object with: id, filename, checksum, wrapped DEK, nonce, etc.
❌ METADATA NOT SAVED TO DATABASE (InMemoryPhotoRepository only)
```

### On App Restart (Today's State):
```
App starts
  ↓
_photoRepository = InMemoryPhotoRepository()
  ↓
Gallery queries _photoRepository.listPhotos()
  ↓
InMemoryPhotoRepository has empty cache (process was killed)
  ↓
Gallery displays: "No photos" (but encrypted files still exist on disk!)
```

### On App Restart (After Drift Fix):
```
App starts
  ↓
_photoRepository = PersistentPhotoRepositoryImpl()
  ↓
_photoRepository.initialize() → opens SQLite connection
  ↓
Gallery queries _photoRepository.listPhotos()
  ↓
SQLite returns all photo records from database
  ↓
Gallery displays all thumbnails (decrypting on-demand)
```

---

## Summary

| Issue | Root Cause | Status |
|-------|-----------|--------|
| Photos not on disk | Misconception — they ARE encrypted on disk | ✅ Working |
| No preview option | Screen created but not wired into router | ⚠️ Partial |
| Photos gone on restart | Metadata never persisted to DB | ❌ Broken |
| Storage location unclear | Not documented in earlier phases | ✅ Fixed (see STORAGE_ARCHITECTURE.md) |

---

## Next Steps to Fix

1. **Implement Drift ORM integration** (critical blocker)
   - Generate typed database classes
   - Implement photo repository SQL queries
   - Photos will persist across restarts

2. **Wire import preview into router** (minor UX improvement)
   - Add /import/preview route
   - Update import review screen to navigate on tap

3. **Test end-to-end persistence**
   - Import photos
   - Close app
   - Reopen app
   - Verify photos in gallery
   - Unlock vault
   - Verify thumbnails decrypt and display
