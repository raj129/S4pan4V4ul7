# photo_vault

Local-first encrypted photo vault (Android-first).

## Overview

photo_vault is a Flutter application that stores photos encrypted locally using AES-GCM and platform-backed secure storage for keys. The project follows a clean architecture with distinct layers: domain, application (usecases/services), data (repositories/datasources), presentation (UI), crypto, and storage.

## Quickstart

Prerequisites: Flutter SDK >= 3.12

1. Install dependencies

   flutter pub get

2. Generate code (drift/build_runner) when needed

   flutter pub run build_runner build --delete-conflicting-outputs

3. Run the app

   flutter run

## Project layout (high level)

- lib/application — usecases and application services (vault_session, import manager, etc.)
- lib/domain — entities and repository interfaces
- lib/data — repository implementations, datasources (local and test helpers)
- lib/presentation — app widgets, screens, state (cubits)
- lib/crypto — crypto services and models
- lib/storage/local_db — drift schema and generated DB (generated files are gitignored)

## Development

- Analyze: flutter analyze
- Tests: flutter test
- Codegen: flutter pub run build_runner build --delete-conflicting-outputs

## Android tester builds (Firebase App Distribution)

The `Flutter CI` GitHub Actions workflow uploads a release APK to Firebase App
Distribution after analysis, tests, and code generation pass on `main`. It can
also be started manually with **Actions → Flutter CI → Run workflow** on `main`.
Pull requests run CI but do not distribute builds.

Before the first upload:

1. In Firebase Console, create a tester group and add tester email addresses.
2. Create a service account with the Firebase App Distribution Admin role and
   create a JSON key for it.
3. Generate a dedicated Android tester-signing keystore with `keytool`, and
   store a secure backup. For example:

   ```powershell
   keytool -genkeypair -v -keystore tester-signing-key.jks -alias tester `
     -keyalg RSA -keysize 2048 -validity 10000
   $bytes = [IO.File]::ReadAllBytes("tester-signing-key.jks")
   [Convert]::ToBase64String($bytes) | Set-Clipboard
   ```

   Paste the clipboard contents into the `ANDROID_KEYSTORE_BASE64` secret. Do
   not commit the keystore to the repository.
4. In the GitHub repository, add these Actions secrets:
   `FIREBASE_SERVICE_ACCOUNT_JSON` (service-account JSON),
   `ANDROID_KEYSTORE_BASE64` (the keystore encoded as one Base64 line),
   `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, and `ANDROID_KEY_PASSWORD`.
5. Add the Actions repository variable `FIREBASE_TESTER_GROUPS` with the Firebase
   tester group alias. Multiple aliases can be comma-separated.
6. Allow GitHub Actions to write repository contents so the workflow can create
   version tags.

The workflow reads the Android Firebase app ID from `firebase.json`. It assigns
the next `0.9.NNN` version by finding the latest successful-upload tag
(`v0.9.001`, `v0.9.002`, and so on), then uploads the APK and creates that tag.
The APK's Android build number is also incremented, starting above the current
`pubspec.yaml` build number. The workflow does not edit or commit `pubspec.yaml`;
the next version tag is created only after Firebase accepts the upload. The
dedicated keystore signs each tester APK consistently so Android can install
updates without requiring testers to uninstall and risk losing local data.
Local release builds continue to use the debug signing configuration unless
tester-signing environment variables are supplied.

After an upload, testers in the configured group receive Firebase's invitation
email and can install the build using the Firebase App Tester app on Android.

## Docs

See STORAGE_ARCHITECTURE.md and PERSISTENCE_FIX_SUMMARY.md for persistence design notes and rationale.

## Notes on generated files

Generated artifacts (for example, drift-generated *.g.dart) are ignored by default and should be produced in CI using build_runner. If you intentionally keep generated outputs committed, document that decision here.

## Contributing

Please open issues or PRs for any improvements. Add a CONTRIBUTING.md for contributor guidelines.
