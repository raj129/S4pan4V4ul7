# Task Progress - Photo Vault Improvements

- [x] **Phase 1: Biometric Removal**
    - [x] Remove Biometric Service usages in `VaultApp`.
    - [x] Update `LockScreen` to remove biometric prompt.
    - [x] Update `SettingsScreen` to remove biometric toggle.
    - [x] Clean up `OnboardingCubit` and onboarding screens.
- [x] **Phase 2: Photo Viewer Fixes**
    - [x] Update `GalleryPhotoViewerScreen` for full-screen fit and zoom.
    - [x] Improve interaction and aspect ratio handling.
- [x] **Phase 3: Performance Optimization**
    - [x] Implement paginated queries in `VaultDatabase`.
    - [x] Update `PersistentPhotoRepository` to use pagination.
    - [x] Implement thumbnail cache limit in `ImportManager`.
- [x] **Phase 4: Change PIN Feature**
    - [x] Implement `ChangePinUseCase`.
    - [x] Create `ChangePinScreen`.
    - [x] Add "Change PIN" action in `SettingsScreen`.
- [x] **Phase 5: Verification**
    - [x] Manual verification of all features.
