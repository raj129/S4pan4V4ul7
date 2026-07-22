# Google Sign-In 7.2.0 API Migration Plan

The `google_sign_in` package version 7.2.0 introduced breaking changes, moving to a singleton pattern and renaming core methods to support the Android Credential Manager.

## Proposed Changes

### 1. Main Initialization [MODIFY] [main.dart](file:///C:/temp/androidshadow4726262/lib/main.dart)
- Initialize `GoogleSignIn.instance` before running the app.

### 2. Auth Repository [MODIFY] [firebase_auth_repository.dart](file:///C:/temp/androidshadow4726262/lib/data/repositories_impl/firebase_auth_repository.dart)
- Switch from constructor-injected `GoogleSignIn` to the `GoogleSignIn.instance` singleton.
- Update `signInWithGoogle`:
    - Use `authenticate()` instead of `signIn()`.
    - Retrieve `accessToken` via the `authorizationClient`.
- Update `getAuthenticatedClient`:
    - Use `attemptLightweightAuthentication()` instead of `signInSilently()`.
    - Retrieve authorization headers via the `authorizationClient`.

## User Review Required

> [!IMPORTANT]
> **Credential Manager:** Version 7.2.0 uses the new Android Credential Manager. This ensures the app is future-proof for Android 14+ but requires these API changes.

## Verification Plan

### Automated Tests
- No changes to existing tests; verify they still pass if they used mocks.

### Manual Verification
- **Google Sign-In Flow:**
    1. Open the app.
    2. Choose "Sign in with Google".
    3. Verify the account picker appears.
    4. Verify successful sign-in and transition to the gallery.
- **Photo Export/Drive Backup:**
    1. Verify that the app can still access Google Drive using the new `authorizationClient` pattern.
