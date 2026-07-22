# Walkthrough - Google Sign-In, Vault Recovery, and Photo Export

I have implemented the requested features to enable cloud and local recovery of your encrypted vault, as well as the ability to export photos to your device's Downloads folder.

## Key Changes

### 1. Google Sign-In & Firebase Integration
- Replaced the stub authentication with a real `FirebaseAuthRepository`.
- Added `google_sign_in` support with required scopes for Google Drive access (`drive.appdata`).
- Users can now sign in with their Google account during onboarding or restore.

### 2. Multi-Destination Vault Recovery (VMK Backup)
- **Google Drive Backup:** Automatically stores your encrypted Vault Master Key (VMK) in the app's private Google Drive folder.
- **Local Recovery File:** Maintains a `vmk_recovery.json` file in the public `Documents/PhotoVault_Recovery/` folder. This file persists even if the app is uninstalled, allowing for easy recovery.
- **Security:** In both cases, the key is stored **encrypted** with your PIN-derived key. Neither Google nor anyone with access to the recovery file can read your photos without your PIN.

### 3. Photo Export
- Added an "Export" feature that decrypts a photo and saves it to the public `Downloads/PhotoVault_Exports/` folder.
- Exported photos are standard image files (JPEG/PNG) that can be viewed by any gallery app on the device.

### 4. Restore Flow
- Implemented `BackupRestoreFlowService` which can automatically scan Google Drive and the local Documents folder to find and restore your vault key after a reinstall or device change.

## Verification Results

### Google Sign-In & Drive
- Verified that sign-in completes and requests the `drive.appdata` scope.
- `GoogleDriveVmkRepository` correctly handles the creation and update of the backup file in the cloud.

### Local Recovery
- Verified that the `PhotoVault_Recovery` folder is created in the public `Documents` directory.
- Confirmed that the `vmk_recovery.json` contains the necessary components for restoration.

### Photo Export
- Verified that tapping the export button in the photo viewer decrypts the photo and writes it to `Downloads`.
- Confirmed that the exported file is a valid image.

> [!IMPORTANT]
> To use Google Sign-In in a production environment, you will need to:
> 1. Configure your SHA-1 fingerprints in the Firebase Console.
> 2. Enable the Google Drive API in the Google Cloud Console for your project.
