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

## Android chat attachment privacy

Received images and videos are downloaded to encrypted, app-private phone
storage when Android permits background work. Receiving an attachment does not
import it into the vault or make it visible in the gallery. The user chooses
**Move to vault**, unlocks the vault, and the local full-media chat copy is removed
only after the encrypted vault import succeeds. The chat message and remote
attachment remain intact; a small encrypted thumbnail can remain in chat history.

Chat attachment caches contain ciphertext only. Decryption is for in-app display
and playback, not external opening or plaintext export. Existing gallery and
document source files selected by the user are not deleted or modified.
Unsupported formats can be stored securely even when an in-app preview is not
available. Private storage and encryption do not protect against a compromised
or rooted device, and managed-runtime memory cannot be guaranteed to be erased.

Background work is subject to Android network, battery, Doze and execution limits.
Force-stopping the application suspends work until Android permits it again,
typically after the application is relaunched. A locked vault never causes an
automatic vault import; background chat work uses separately protected chat keys.

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

### Android chat attachments

Android queues encrypted attachments in an app-private durable journal protected
by Android Keystore. Transfers expose byte progress and queued, uploading, paused,
completed, failed, cancelled, retrying and resumed states. Pause/resume/cancel and
explicit retry retain the same message identity; restart recovery reconciles
remote objects and commits messages transactionally to avoid duplicate messages
and unread counts. Network-constrained WorkManager work retries offline queues,
while active transfers use Android foreground-service notifications.
Each pending attachment has one progress component with processed/total transfer
bytes, percentage and applicable pause/resume/retry/cancel actions. Deleting a
pending message cancels its transfer and removes its encrypted staging files.
Expired Firebase upload sessions restart the same ciphertext safely; paused
jobs do not resume merely because connectivity returns.

Received images and videos download into an account-scoped ciphertext cache.
They are **not automatically imported into the vault**. **Move to vault** requires
an unlocked vault, encrypts the attachment directly, and removes the full chat
cache copy only after a durable, authenticated import. Interrupted committed
moves resume on thread reopen or vault unlock; moved markers prevent background
redownload. Original files selected from other apps are not deleted.

Document/gallery acquisition, recording, image preview, audio/video playback
and supported PDF preview do not create chat plaintext files or launch external
viewers. Chat keeps the original external Android camera experience: the camera
app can create plaintext before handing the captured result back. Returned
photos are encrypted promptly for lock/restart recovery; only camera-generated
copies inside this app's temporary directory are removed, never gallery
originals. Recovered captures require confirmation before sending.
Recording supports start/pause/resume/cancel/stop, uses encrypted audio spools,
and closes after durable queue acceptance (including offline). Videos preserve
their aspect ratio and use modern Android Media3 playback controls. Native
chat viewer dialogs do not trigger the background lock merely by taking window
focus; sending the app to the background still applies the normal lock policy. Other
attachment formats can be stored in the vault without preview. Attachments are
limited to less than 64 MB; PDF preview requires Android 8 or newer. Background
processing requires available chat keys and remains subject to Android network,
foreground-service, battery and force-stop restrictions. Vault keys are never
unlocked by background work.

See STORAGE_ARCHITECTURE.md and PERSISTENCE_FIX_SUMMARY.md for persistence design notes and rationale.

## Notes on generated files

Generated artifacts (for example, drift-generated *.g.dart) are ignored by default and should be produced in CI using build_runner. If you intentionally keep generated outputs committed, document that decision here.

## Contributing

Please open issues or PRs for any improvements. Add a CONTRIBUTING.md for contributor guidelines.
