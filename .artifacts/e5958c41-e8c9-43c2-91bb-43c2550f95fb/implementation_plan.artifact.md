# Google Sign-In, Recovery, and Photo Export Implementation Plan

This plan details the implementation of Google Sign-In using Firebase, the multi-destination backup system for the Vault Master Key (VMK), and the photo export functionality.

## Goals
Enable users to:
1.  **Recover their vault** after a device change or app reinstall using Google Drive or local recovery files.
2.  **Export their photos** from the encrypted vault back to the device's **Downloads** folder.
3.  **Local Maintenance:** Store the local VMK recovery file in the **Downloads/VaultBackup/** directory. This ensures it survives app uninstallation (unlike the `Android/media/` folder, which is deleted when the app is removed).

## User Review Required

> [!IMPORTANT]
> **Security Model:** The VMK backed up to Google Drive or Local Storage is **wrapped (encrypted)** with the user's PIN-derived key. Google or anyone with access to the backup file cannot read the vault without the PIN.
> 1. We will use the `drive.appdata` scope for Google Drive, meaning the app can only see files it created.
> [!NOTE]
> **VML vs VMK:** We assume "VML" in your request refers to the "VMK" (Vault Master Key) mentioned in the codebase. Both refer to the encrypted key material needed to unlock your photos.

## Proposed Changes

### 1. Dependencies [MODIFY] [pubspec.yaml](file:///C:/temp/androidshadow4726262/pubspec.yaml)
- Add `google_sign_in: ^6.2.1`
- Add `googleapis: ^13.2.0`
- Add `googleapis_auth: ^1.6.0`
- Add `http: ^1.2.1` (required by googleapis)

### 2. Domain Layer
#### [NEW] [vmk_backup_repository.dart](file:///C:/temp/androidshadow4726262/lib/domain/repositories/vmk_backup_repository.dart)
- Define `VmkBackupRepository` interface with `backupVmk` and `restoreVmk` methods.

### 3. Data Layer
#### [NEW] [firebase_auth_repository.dart](file:///C:/temp/androidshadow4726262/lib/data/repositories_impl/firebase_auth_repository.dart)
- Implementation of `AuthRepository` using `firebase_auth` and `google_sign_in`.
- Will handle Google Sign-In and provide the `AuthResult` with the user's email and ID.

#### [NEW] [google_drive_vmk_repository.dart](file:///C:/temp/androidshadow4726262/lib/data/repositories_impl/google_drive_vmk_repository.dart)
- Implementation of `VmkBackupRepository` for Google Drive.
- Uses `googleapis` to manage a `vmk_backup.json` file in the app's private Drive folder (`appDataFolder`).

#### [NEW] [local_vmk_backup_repository.dart](file:///C:/temp/androidshadow4726262/lib/data/repositories_impl/local_vmk_backup_repository.dart)
- Implementation of `VmkBackupRepository` for local storage.
- Will save/load the wrapped VMK from a user-specified or convention-based path (e.g., in the photo root folder).

### 4. Application Layer
#### [NEW] [export_photo_usecase.dart](file:///C:/temp/androidshadow4726262/lib/application/usecases/export_photo_usecase.dart)
- Orchestrates decryption and saving to public storage.
- 1. Fetch `VaultPhoto` and its `wrapped_dek`.
2. Unwrap DEK using VMK.
3. Decrypt photo file using DEK.
4. Save to the public **Downloads** folder via `MediaStore` (on Android) to ensure compatibility with Scoped Storage and visibility to the user.

#### [MODIFY] [create_vault_usecase.dart](file:///C:/temp/androidshadow4726262/lib/application/usecases/create_vault_usecase.dart)
- Inject `VmkBackupRepository` (factory or multi-repo).
- After successful local creation, trigger backup to the appropriate destination based on `UserMode`.

#### [MODIFY] [restore_flow_service.dart](file:///C:/temp/androidshadow4726262/lib/application/services/restore_flow_service.dart)
- Implement `restoreEncryptedVmk` to attempt fetching from Google Drive or Local Storage.

### 5. Presentation Layer
#### [MODIFY] [onboarding_cubit.dart](file:///C:/temp/androidshadow4726262/lib/presentation/state/onboarding/onboarding_cubit.dart)
- Update to handle the new backup steps and potential errors during backup.

#### [NEW] UI for Export
- Add "Export" button to the photo detail screen and multi-select menu in the gallery.

## Verification Plan

### Automated Tests
- Unit tests for `FirebaseAuthRepository` (using mocks for Firebase/GoogleSignIn).
- Integration tests for `VmkBackupRepository` implementations with mock clients.

### Manual Verification
- **Google Flow:**
    1. Select "Sign in with Google".
    2. Complete Sign-In.
    3. Create Vault.
    4. Verify `vmk_backup.json` is created in Google Drive (via Drive API Explorer or logs).
    5. Reinstall app, choose Google, and verify "Restore" works.
- **Local Flow:**
    1. Select "Continue Locally".
    2. Create Vault.
    3. Verify a backup file is created in the specified external storage path.
- **Export Flow:**
    1. Select a photo in the gallery.
    2. Tap "Export".
    3. Verify the photo appears in the device's public "Pictures" or "Downloads" folder and is viewable by other apps.
