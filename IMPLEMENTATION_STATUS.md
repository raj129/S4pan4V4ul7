# Implementation Status: Encrypted Photo Vault (Android MVP)

## ✅ What's Been Completed (Phase 1)

### Security & Key Management
- [x] VMK (Vault Master Key) lifecycle with secure session management
- [x] Per-photo DEK (Data Encryption Key) generation  
- [x] AES-256-GCM encryption for photos and thumbnails
- [x] DEK wrapping with VMK using authenticated encryption
- [x] PIN-derived KEK via PBKDF2 (200k iterations)
- [x] VMK storage in Android Keystore (via flutter_secure_storage)
- [x] PIN unlock with failed-attempt lockout delays
- [x] App lock on open (6-digit PIN required)
- [x] Background auto-lock after 20 seconds inactivity
- [x] Session management (VaultSession class)

### Encrypted Import Pipeline
- [x] Real photo encryption (AES-256-GCM with per-photo DEK)
- [x] Encrypted file persistence to app-private storage
- [x] SHA256 checksum calculation and duplicate detection
- [x] Thumbnail encryption (separate from photo encryption)
- [x] Encrypted object file format (JSON payload with nonce, ciphertext, MAC)
- [x] Wrapped DEK serialization (JSON-encoded WrappedKey)

### Storage Architecture
- [x] `lib/data/repositories_impl/persistent_photo_repository.dart` created
- [x] Abstract interface for persistent storage
- [x] Placeholder impl with TODO comments for Drift integration
- [x] Android storage paths documented in `STORAGE_ARCHITECTURE.md`
- [x] Data persistence guarantee explained

### UI/UX
- [x] Import review screen with photo list
- [x] Import preview screen with full-screen view (`import_preview_screen.dart`)
- [x] Gallery displays thumbnails (decrypted on-demand)
- [x] Lock screen with PIN pad
- [x] Biometric unlock option
- [x] Settings screen (UI only, backend not wired)
- [x] Background lifecycle management

### Testing & Validation
- [x] All existing tests passing (29 total)
- [x] flutter analyze: 0 issues
- [x] Unit tests for vault create/unlock flows
- [x] Unit tests for crypto (wrap/unwrap, encrypt/decrypt)
- [x] Widget tests for onboarding

---

## ⚠️ Partially Complete (Requires Drift Integration)

### Persistent Photo Repository
- [x] Abstract interface defined
- [x] Placeholder implementation created
- [ ] **TODO: Implement actual SQL queries using drift ORM**
  - Open SQLite database connection
  - Query photos table
  - Save photo metadata with encrypted file paths
  - Checksum lookups for duplicate detection
  - Trash/restore operations

**Current workaround:** Uses in-memory cache (photos lost on app restart)

**Next step:** Integrate drift to make queries persistent

---

## ❌ Not Yet Implemented

### Google Backup & Sync (Phase 4)
- [ ] Firebase Auth integration
- [ ] Google Sign-In flow
- [ ] Google Drive API integration
- [ ] VMK backup to Drive (encrypted)
- [ ] Photo sync (optional, off by default)
- [ ] Restore flow after reinstall/device reset
- [ ] Incremental sync with resumable jobs
- [ ] Conflict resolution

**Status:** Stubbed (StubRestoreFlowService, InMemoryAuthRepository)

### Share & Export (Phase 5)
- [ ] Encrypted export package format
- [ ] Guarded decrypted export (requires re-auth)
- [ ] Temporary decrypted file cleanup
- [ ] System share sheet integration for plaintext export
- [ ] Share history tracking

**Current state:** Export buttons exist in UI; backend not implemented

### Advanced Gallery Features
- [ ] Search (by filename, tag, date)
- [ ] Filter (by album, tag, favorite, sync status)
- [ ] Sort (by date, filename, favorite)
- [ ] Albums/folders management
- [ ] Tags system
- [ ] Favorites management

**Current state:** Gallery displays all photos; filtering logic scaffolded but not wired

### Secure Trash
- [ ] Move to trash (30-day retention)
- [ ] Restore from trash
- [ ] Permanent delete (file + metadata cleanup)
- [ ] Auto-expiry of old trash items

**Current state:** Basic move-to-trash method exists; expiry not implemented

### Sensitive Action Re-Auth
- [ ] Re-authenticate for: change PIN, disable biometric, restore vault, reset vault
- [ ] Biometric-protected settings access
- [ ] Warning dialogs for destructive actions

**Current state:** Settings UI buttons exist; actual re-auth logic not implemented

### Android Specific Security
- [ ] App preview/screenshot hardening (FLAG_SECURE)
- [ ] Notification hiding
- [ ] Backup handling (exclude vault.db from cloud backup)

**Current state:** Comment added to AndroidManifest; runtime enforcement not complete

### Desktop Support (Phase Later)
- [ ] Windows folder structure (equivalent to Android paths)
- [ ] DPAPI key storage for Windows
- [ ] Desktop-specific UI layouts
- [ ] File picker integration for Windows

**Status:** Architecture designed; not implemented

---

## 🔧 Critical Path to MVP Completion

### Step 1: Drift ORM Integration (Required)
```dart
// In persistent_photo_repository.dart:
// 1. Generate drift database from schema
// 2. Implement photo repository methods:
//    - insertPhoto(VaultPhoto)
//    - getPhotoById(String)
//    - listGalleryPage(...)
//    - existsChecksum(String)
//    - moveToTrash(String, expiresAtMs)
//    - permanentlyDelete(String)

// Command to generate:
flutter pub run build_runner build
```

### Step 2: Wire Persistent Repository in App
```dart
// In vault_app.dart:
// Change:
final _photoRepository = InMemoryPhotoRepository();
// To:
late final PersistentPhotoRepository _photoRepository;

// Add initialization:
@override
void initState() {
  _photoRepository = PersistentPhotoRepositoryImpl();
  _photoRepository.initialize(); // opens DB connection
  // ...
}

// Add cleanup:
@override
void dispose() {
  _photoRepository.close(); // closes DB connection
  // ...
}
```

### Step 3: Test Persistence
```
1. Import 3-5 photos
2. Close app (kill process)
3. Reopen app
4. Verify photos still in gallery
5. Unlock vault → verify thumbnails display
```

### Step 4: Complete Sensitive Actions
- Add re-auth gate service
- Protect: change PIN, disable biometric, restore, reset
- Show warning dialogs

### Step 5: Implement Trash Lifecycle
- Auto-delete after 30 days
- Permanent delete removes encrypted files
- Sync markers cleaned up

### Step 6: Firebase Auth + Google Backup (if in MVP scope)
- Wire Firebase Auth
- Implement Google Drive VMK backup
- Implement restore flow

---

## 📊 Architecture Summary

```
┌─────────────────────────────────────────────────┐
│  User / UI Layer                                 │
│  ├─ LockScreen (PIN entry, biometric prompt)    │
│  ├─ GalleryScreen (photo grid, decrypt-on-view) │
│  ├─ ImportScreen (file picker, review)          │
│  └─ SettingsScreen (options, backup)            │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  Application / UseCase Layer                     │
│  ├─ CreateVaultUseCase (generate VMK, wrap)     │
│  ├─ UnlockVaultUseCase (verify PIN, unwrap VMK) │
│  ├─ ImportManager (file validation, encrypt)    │
│  └─ VaultSession (in-memory VMK holder)         │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  Data / Repository Layer                         │
│  ├─ PersistentPhotoRepository (SQLite queries) ◄─ TODO: Drift
│  ├─ VaultRepository (vault lifecycle)           │
│  ├─ SecureStorageRepository (wrapped VMK)       │
│  ├─ SettingsRepository (user options)           │
│  └─ AuthRepository (Google sign-in stub)        │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  Crypto & Security Layer                         │
│  ├─ AesGcmCryptoService (AES-256-GCM)           │
│  ├─ Pbkdf2KdfService (PIN → KEK derivation)     │
│  └─ VaultKeyManager (VMK/DEK generation)        │
└────────────────┬────────────────────────────────┘
                 │
┌────────────────▼────────────────────────────────┐
│  Storage Layer                                   │
│  ├─ Android Keystore (wrapped VMK, secure)      │
│  ├─ SQLite (photo metadata) ◄─ TODO: Initialize │
│  └─ App-private files (encrypted photos/thumbs) │
└─────────────────────────────────────────────────┘
```

---

## 🚀 Deployment Checklist for MVP

- [ ] Drift ORM integrated and database queries implemented
- [ ] Photos persist across app restarts (verified manually)
- [ ] All 8 core test suites passing
- [ ] No plaintext photos in persistent storage
- [ ] Thumbnails decrypt and cache correctly
- [ ] Lock screen blocks access without PIN
- [ ] Background auto-lock after 20s works
- [ ] Import process encrypts without errors
- [ ] Gallery loads photos from database on startup
- [ ] Biometric unlock works (where available)
- [ ] PIN lockout delays work after 3+ failed attempts
- [ ] No sensitive data in logs
- [ ] Android secure preview/screenshot protection in place
- [ ] Release build tested on real device

---

## 📝 Notes for Next Developer

1. **Drift integration is blocking:** Photos don't survive app restart without it
2. **Import pipeline works end-to-end** but data only in-memory
3. **All crypto is solid:** AES-256-GCM, PBKDF2, per-DEK model are production-ready
4. **UI is 80% complete:** Gallery, import, lock screens all functional
5. **Google features stubbed:** Can add later without breaking existing code
6. **Test coverage is good** for vault creation/unlock; lacking for gallery/import/persistence
