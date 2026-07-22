# Implementation Plan - Biometric Removal, Change PIN, Performance, and Photo Viewer Fix

This plan addresses the removal of biometric features, the addition of a secure "Change PIN" workflow, performance improvements for large photo libraries, and fixing the photo viewer's zoom and display issues.

## User Review Required

### Performance Analysis (>1K Photos)
> [!NOTE]
> **Database:** SQLite (via Drift) can easily handle 10,000+ records. However, the current code fetches *all* records into memory for pagination. I will optimize this to use SQL-level LIMIT/OFFSET.
> **Memory:** The thumbnail cache currently grows indefinitely. For 1000+ photos, this could cause Out-Of-Memory (OOM) crashes. I will implement a size-limited cache (LRU).

### Change PIN Risk
> [!WARNING]
> **Data Loss Risk:** If the process of updating the PIN is interrupted (crash, power loss), the Vault Master Key (VMK) could be lost, making all photos permanently unreadable.
> **Mitigation:** I will implement an atomic-like update:
> 1. Derive new key and wrap VMK.
> 2. Save the new "envelope" to a temporary key in secure storage.
> 3. Verify the temporary key can be decrypted with the new PIN.
> 4. Overwrite the main key with the temporary one.

## Proposed Changes

### [Component] Biometric Removal
Remove all biometric-related UI and logic.

#### [MODIFY] [vault_app.dart](file:///C:/temp/androidshadow4726262/lib/presentation/app/vault_app.dart)
- Remove `_biometricService` and related initialization.
- Remove biometric branch from onboarding redirect logic.

#### [MODIFY] [lock_screen.dart](file:///C:/temp/androidshadow4726262/lib/presentation/screens/lock/lock_screen.dart)
- Remove biometric prompt and "Try biometric again" button.

#### [MODIFY] [settings_screen.dart](file:///C:/temp/androidshadow4726262/lib/presentation/screens/settings/settings_screen.dart)
- Remove "Biometric unlock" toggle.

---

### [Component] Change PIN Feature
Implement a secure workflow to update the app PIN.

#### [NEW] [ChangePinUseCase](file:///C:/temp/androidshadow4726262/lib/application/usecases/change_pin_usecase.dart)
- Logic to re-wrap VMK with a KEK derived from a new PIN.

#### [MODIFY] [settings_screen.dart](file:///C:/temp/androidshadow4726262/lib/presentation/screens/settings/settings_screen.dart)
- Add "Change PIN" button.
- Navigate to a new `ChangePinScreen`.

#### [NEW] [ChangePinScreen](file:///C:/temp/androidshadow4726262/lib/presentation/screens/settings/change_pin_screen.dart)
- UI to enter old PIN (validation) and then new PIN (confirmation).

---

### [Component] Performance Optimization
Improve database and memory efficiency for large libraries.

#### [MODIFY] [vault_database.dart](file:///C:/temp/androidshadow4726262/lib/storage/local_db/vault_database.dart)
- Add paginated query methods using Drift's `limit` and `offset`.

#### [MODIFY] [persistent_photo_repository.dart](file:///C:/temp/androidshadow4726262/lib/data/repositories_impl/persistent_photo_repository.dart)
- Update `listGalleryPage` to use the new paginated database queries.

#### [MODIFY] [import_manager.dart](file:///C:/temp/androidshadow4726262/lib/application/services/import_manager.dart)
- Implement a maximum size for `_thumbnailMemoryCache` (e.g., 200 items) to prevent memory bloating.

---

### [Component] Photo Viewer Fixes
Fix zoom, full-screen, and aspect ratio issues.

#### [MODIFY] [gallery_photo_viewer_screen.dart](file:///C:/temp/androidshadow4726262/lib/presentation/screens/gallery/gallery_photo_viewer_screen.dart)
- **Full Screen:** Use `BoxFit.contain` within an `InteractiveViewer` that spans the entire available space.
- **Background:** Ensure the background is pure black to match standard viewers.
- **Interaction:** Improve `InteractiveViewer` parameters (e.g., `clipBehavior: Clip.none`) to ensure the photo can be zoomed fully without clipping artifacts.
- **Layout:** Remove any unnecessary padding or centering that might restrict the image size.

---

## Verification Plan

### Automated Tests
- Unit test for `ChangePinUseCase` ensuring the VMK is correctly re-wrapped.

### Manual Verification
1. **Biometric Removal:** Verify no mention of biometrics in UI.
2. **Change PIN:** Verify unlock works with NEW PIN and fails with OLD PIN.
3. **Performance:** Verify gallery scrolling remains smooth with many photos.
4. **Photo Viewer:** Open photos of various aspect ratios (portrait/landscape) and verify they fit correctly and zoom as expected.
