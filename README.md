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

- `lib/features/chat` — chat domain, application services, media/attachment workflow,
  data adapters, presentation, and chat-specific dependency composition.
- `lib/features/vault` — vault domain, application services/use cases, persistence
  adapters, and vault screens/state.
- `lib/features/calculator` — the calculator feature and its domain, state, and UI.
- `lib/core` — app-wide routing and dependency composition, shared crypto primitives,
  local database, shared UI, and cross-feature session/integration code.
- `lib/main.dart` and `lib/firebase_options.dart` — application entry point and
  Firebase configuration.

Chat media selection, image preparation/compression, encryption orchestration,
upload/download, local media, and preview are grouped under the chat feature.
Reusable cryptographic primitives remain in `lib/core/crypto`; animated emoji
remain a chat presentation component. Android chat platform/plugin code remains
in the Android app and `packages/android_chat_downloads`.

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
Local release builds require the tester-signing environment variables, or
`allowDebugSigning=true` in your user-level `~/.gradle/gradle.properties` for
throw-away experiments; a debug-signed release APK must never be distributed.

After an upload, testers in the configured group receive Firebase's invitation
email and can install the build using the Firebase App Tester app on Android.

## Docs

### Notes and checklists

In a chat, use the attachment sheet's **Note** or **Checklist** action to
create a shared item. **Notes & Lists** in the same sheet shows that chat's
existing shared items, newest edit first, with local edit dates and times.
The navigation drawer's **Notes & Lists** shows separate private notes stored
on this device. The editor saves as you work; the checkmark saves and returns
to the list or chat. Press Enter while editing a checklist item to move to an
empty item field.

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
Upload pause preserves the Firebase resumable session. After pause, network loss,
or process restart, valid sessions continue from the server-confirmed offset;
expired sessions may require a restart rather than pretending saved bytes were
accepted. Recovery also checks uploads finalized before a local checkpoint was
written, retaining the original object and message identity.

Android downloads use a native, automatically registered WorkManager plugin
shared by foreground and headless Flutter engines. Encrypted partial files and
durable offsets survive process death. HTTP range requests resume against the
same object generation; changed objects, rejected offsets, or servers ignoring
range requests safely restart rather than append incompatible bytes. Download
controls report byte progress and support pause, resume, retry, and cancellation.
Cancelled partials are removed; authenticated cache commits acknowledge staging
copies for delayed cleanup. Staging is limited to 192 MB and 128 jobs, with a
two-minute acknowledged-read grace period and seven-day inactive-job expiry.

Large attachment authentication runs on a short-lived Dart worker instead of the
UI isolate. The existing encryption format is unchanged: the complete file must
be downloaded and authenticated before playback, so a cold large-video open is
still affected by network speed. Loading displays transfer and preparation
stages; debug/profile builds record content-free stage timings to distinguish
network, cache, authentication, dispatch, and first-frame delays.

Completed received attachments live in app-private `chat_received_media`,
separate from resumable download staging. `chat_sent_media` retains encrypted
sent copies. Their account-qualified index and original-source descriptors are
sealed with Android Keystore; source URIs never go to Firestore. The directories
share a 150 MB completed-media budget. Completed received files are retained
until explicit removal or vault import, including across app restarts and
sign-out; storage exhaustion reports an error rather than silently evicting
files. Deleting an attachment message removes its local copies and pending
downloads without deleting the user's original external file.

Received previews reopen complete local ciphertext without another network
download. Existing encrypted cache entries migrate when successfully read.
Sent previews prefer an unchanged, accessible original source URI/file, then an
existing encrypted local sent copy. Missing/revoked/changed sources trigger that
local fallback, never a server download. Older sent attachments with neither
source nor a local encrypted copy report unavailable and require the original
file to be reselected. Android document grants are retained only where the
provider permits it; transient grants are not assumed to survive a restart.
Persisted grants are not automatically revoked during chat cleanup because the
same grant may be used by another feature. Removing a chat attachment never
deletes or modifies its original external file.

Image, video, audio and supported PDF previews use the existing in-app viewers.
Other file formats remain encrypted with an unsupported-preview explanation and
vault access; no temporary plaintext export to external apps is introduced.
Background receipt retains completed encrypted downloads without decrypting
media. Transport length/version and available server checksums are checked;
full GCM authentication is performed when opening or importing the attachment,
before any plaintext is displayed or played. Native/provider byte buffers are
copied before secure cleanup, and concurrent
preview consumers own independent buffers. Playback/decryption is on demand,
with no app-managed plaintext media directory.

Received images and videos can be acquired in the background where permitted.
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

See docs/STORAGE_ARCHITECTURE.md and docs/STORAGE_FAQ.md for persistence design notes and rationale.

## Notes on generated files

Generated artifacts (for example, drift-generated *.g.dart) are ignored by default and should be produced in CI using build_runner. If you intentionally keep generated outputs committed, document that decision here.

## Contributing

Please open issues or PRs for any improvements. Add a CONTRIBUTING.md for contributor guidelines.
