# Task: Fix Google Sign-In 7.2.0 API

- [x] Migrate `google_sign_in` to 7.2.0 API
    - [x] Initialize `GoogleSignIn.instance` in `main.dart` with `serverClientId`
    - [x] Refactor `FirebaseAuthRepository` to use singleton and new methods
    - [x] Update `idToken` and `accessToken` retrieval logic via `authorizationClient`
- [x] Verify build and sign-in flow
