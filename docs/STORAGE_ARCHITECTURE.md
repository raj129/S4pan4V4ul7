## Encrypted Photo Vault — Android Storage & Persistence Architecture

### Android Storage Paths

**SQLite Database (Photo metadata):**
```
/data/data/com.example.photo_vault/databases/vault.db
```
- Stores all photo metadata: ID, filename, checksums, encrypted file paths, wrapped DEKs, nonces
- Survives app restarts and uninstall (until app is fully removed)
- Encrypted in transit and encrypted at rest by Android Keystore

**Encrypted Photo & Thumbnail Files:**
```
/data/data/com.example.photo_vault/files/vault/objects/
  ├── {photoId}.photo.enc      (encrypted full-size photo)
  ├── {photoId}.thumb.enc      (encrypted thumbnail)
  └── ...
```
- App-private storage (not accessible by other apps without root)
- Each file contains:
  - AES-256-GCM ciphertext of the photo
  - 96-bit nonce (unique per encryption)
  - 128-bit authentication tag (GCM proof of integrity)
  - Encryption version marker
- Files survive app restarts; access requires vault unlock

**Android Keystore (Wrapped VMK):**
```
Android Keystore (SecureStorage)
├── vault.{vaultId}.wrapped_vmk  (AES-256-GCM-encrypted VMK)
├── vault.{vaultId}.nonce        (nonce for VMK wrapping)
├── vault.{vaultId}.mac          (GCM tag for VMK wrapping)
├── vault.{vaultId}.salt         (PBKDF2 salt for PIN derivation)
└── vault.{vaultId}.enc_version  (encryption scheme version)
```
- Hardware-backed (TEE) when available (Nexus 6 and later)
- Survives app restarts; access requires device unlock if configured

---

### Data Flow: Import → Encrypt → Store → Restart

**1. User selects photo in gallery picker**
   - File path: `/sdcard/Pictures/photo.jpg` or `/storage/emulated/0/DCIM/photo.jpg`
   - Stays on filesystem until import is confirmed

**2. User taps "Confirm import"**
   - ImportManager reads plaintext bytes from source file
   - Calculates SHA256 checksum
   - Checks for duplicate (query SQLite `photos` table)
   - If duplicate → skip; if new → proceed

**3. Encryption happens in background isolate (not main thread)**
   - Generate random DEK (256-bit)
   - AES-256-GCM encrypt photo bytes with DEK
   - AES-256-GCM encrypt thumbnail bytes with DEK
   - Wrap DEK with VMK (using app PIN-derived KEK)
   - Write encrypted payload to `/data/data/com.example.photo_vault/files/vault/objects/{photoId}.photo.enc`
   - Write encrypted thumbnail to `/data/data/com.example.photo_vault/files/vault/objects/{photoId}.thumb.enc`

**4. Save metadata to SQLite**
   - INSERT into `photos` table:
     - `id`: {photoId}
     - `encrypted_file_path`: `/data/data/.../files/vault/objects/{photoId}.photo.enc`
     - `thumbnail_path`: `/data/data/.../files/vault/objects/{photoId}.thumb.enc`
     - `wrapped_dek`: JSON-encoded WrappedKey (DEK encrypted by VMK)
     - `checksum_sha256`: hex-encoded SHA256 hash
     - `photo_nonce`: base64-encoded nonce used for photo encryption
     - `thumbnail_nonce`: base64-encoded nonce used for thumbnail encryption
     - `original_filename`: user-friendly name
     - `created_time_ms`, `imported_time_ms`: timestamps
     - `mime_type`: `image/jpeg`, etc.
     - `encryption_version`: 1 (for future migrations)
     - `is_trashed`: 0 (not in trash)
     - `sync_status`: `local` (not yet synced)

**5. App closes**
   - VMK in session memory is zeroed
   - Vault is locked (session cleared)
   - Encrypted files remain on disk
   - SQLite database remains on disk
   - Wrapped VMK remains in Android Keystore

**6. App reopens**
   - Lock screen shown
   - User enters PIN → `UnlockVaultUseCase` unwraps VMK
   - VMK stored in session memory (in VaultSession)
   - Gallery screen queries SQLite `photos` table
   - Displays list of VaultPhoto records with encrypted file paths
   - When thumbnail is needed:
     - Decrypt DEK using VMK
     - Decrypt thumbnail file using DEK
     - Cache in memory (LRU with limit)
     - Display to user

---

### Key Security Guarantees

| Layer | Protection | How |
|-------|-----------|-----|
| **Encrypted files** | Unreadable without DEK | AES-256-GCM; only DEK holder can decrypt |
| **DEKs** | Unreadable without VMK | Wrapped with VMK; only unwrappable with correct PIN |
| **VMK** | Unreadable without PIN | Wrapped with PIN-derived KEK; PBKDF2(PIN, salt) |
| **PIN** | Protected from guessing | PBKDF2 200k iterations; lockout delays after failed attempts |
| **Wrapped blobs** | Authenticated | GCM provides AEAD (ciphertext + authentication tag) |

---

### Plaintext Lifecycle (Minimized)

1. ✅ **User selects photo** → plaintext file read from gallery/camera/share-intent
2. ✅ **Hashing & duplicate check** → plaintext bytes hashed in memory
3. ✅ **Encryption** → plaintext → AES-256-GCM → ciphertext (DEK zeroed after use)
4. ✅ **Threshold: entire plaintext never written to persistent storage** ✅

On import → file is hashed, encrypted, and deleted/overwritten immediately. No plaintext persists.

---

### Future: Photo Sync & Restore

**Google Drive Backup (if enabled):**
- Only encrypted payloads and metadata checksums sync to Drive
- VMK backup is wrapped and encrypted separately
- Plaintext photos never leave device

**Restore after reinstall:**
1. Sign in with Google
2. Fetch encrypted VMK backup from Drive
3. User creates new PIN
4. Re-wrap VMK with new PIN-derived KEK
5. Store wrapped bundle locally
6. Restore encrypted photo metadata
7. Download encrypted photo files on demand

---

### Verification Checklist

- [ ] Encrypted files are written to app-private storage (`getApplicationSupportDirectory()`)
- [ ] Photo metadata (paths, wrapped DEKs, checksums) are persisted to SQLite
- [ ] On app restart, gallery loads photos from SQLite (not in-memory only)
- [ ] Thumbnails are decrypted on-demand and cached temporarily
- [ ] DEKs are wrapped with VMK and never stored plaintext
- [ ] VMK is stored wrapped in secure storage, never plaintext
- [ ] Failed unlock attempts trigger lockout delays
- [ ] Background lock clears session after 20 seconds
