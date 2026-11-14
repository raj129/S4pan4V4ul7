# Private APK and data SMS

This Android build is for private APK distribution, **not Google Play publication**.
It requests `SEND_SMS` and `RECEIVE_SMS`, permissions restricted by Google Play.
The app is not a default SMS handler and no applicable Play exception has been
approved. Sideloading avoids Play distribution, not Android permission prompts.
This does not mean every SMS-capable app is prohibited from Google Play.

## Setup

Build with the repository's existing Firebase/signing configuration:

```powershell
flutter build apk --release
```

Release signing requires `ANDROID_KEYSTORE_PATH` and the existing signing
configuration described in the README. For local testing without release signing:

```powershell
flutter build apk --debug
```

The test APK is `build\app\outputs\flutter-apk\app-debug.apk` and is debug-signed,
not a production-signed release.

Install the resulting APK from a trusted source on both Android phones. Allow
installation from that source in Android settings. Do not share signing keys.

## Sending a data message

1. Sign in, unlock chat, and open the same conversation online on **both phones**
   first to establish encryption keys.
2. Tap the recipient's name at the top of the chat, then **Data SMS number**.
   Choose a number from contacts or enter it manually, including `+` and country
   code, then **Save**. If a contact has multiple numbers, select the intended
   number. Local numbers require you to add the country code; it is never guessed.
   Contacts permission is requested only when choosing from contacts. Manual entry
   remains available if access is denied. Reopen this setting to change or remove
   the number. It is saved only on your device for this chat account, **not
   verified**, and not published to the recipient's profile. Check carefully; a
   wrong number can incur charges.
3. Enable Data SMS and accept the SMS permission prompt on **both phones** before
   going offline, including the phone that will only receive. On dual-SIM phones,
   configure a default SMS SIM in system settings; ambiguous selection is rejected.
4. Type your text, check `characters/SMS segments`, and press **Send**. Stay within
   the 10-segment limit. Cellular SMS service must remain available, even when
   Wi-Fi and mobile data are off.
5. Check the bubble's delivery status in the same conversation. **Device
   delivered** confirms carrier reports for every segment, not app receipt or reading.

Saving a number does not enable SMS or send a message. Select **Data SMS** above
the composer to enable it; this also offers number setup if no number is saved.
The SIM-card icon in Data SMS mode opens the same editor. The other person's app
version does not control whether these settings appear on your phone. Data SMS
requires the Android app with its local chat database; it is not offered on
unsupported platforms.

## Debug and release feature parity

Both variants use the same application ID, main manifest, native plugin
registration, Dart entry point, assets and feature code. Data SMS is not a
debug-only feature. The source audit found no user-facing feature disabled by
build mode:

| Area | Shared debug/release implementation |
|---|---|
| Calculator and vault | Disguise, PIN flows, encrypted storage, screenshot protection, media import/viewing |
| Chat | Internet/data SMS in one timeline, media, message actions, notifications, counters and delivery status |
| Android integrations | Sharing, contacts/call logs, uploads/downloads, background jobs and arrival alerts |
| Location | Maps, search/routes, location sharing and mock location |
| Account and backup | Firebase, Google sign-in and encrypted backups |

Release intentionally removes debug logs, media startup timing instrumentation,
assertions and expanded Maps diagnostic details. Assertions do not enable
features or perform required work. Release also uses optimized/AOT code,
tree-shaken icon fonts and a non-debuggable runtime. These are not missing features.

The CI distribution job builds both variants from the same commit, version and
API-key configuration, then runs `tool\verify_apk_parity.ps1` before uploading the
signed release. It compares normalized merged manifests (including permissions,
components, intent filters, SDKs and metadata), Flutter assets and supported ABIs.
It explicitly checks SMS routing, required app components, release AOT code and
vault backup protection. It does **not** prove runtime behavior, inspect every
native method after optimization, validate signing certificates, or authorize APIs.

For local verification, build both variants with the same configuration, then run:

```powershell
flutter build apk --debug --dart-define-from-file=.api_keys.json
flutter build apk --release --dart-define-from-file=.api_keys.json
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\verify_apk_parity.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\test\tool\apk_parity_test.ps1
```

Use the existing signing environment for the release command. The checker needs
Java, Android SDK command-line tools (`latest`) and build-tools. Set `ANDROID_HOME`
or pass `-Sdk`. `-DebugApk` and `-ReleaseApk` accept alternative artifact paths.
Do not publish decoded manifests or resource dumps: they contain API keys.

Google services also depend on configuration outside the APK. Register the actual
release signing SHA-1/SHA-256 in the Firebase Android app as required, configure
Google sign-in for that certificate, refresh `google-services.json` when required,
and authorize both debug and release SHA-1 certificates in Android API-key
restrictions for Maps/search/routes. Enable the required APIs. Identical feature
code cannot compensate for a missing release certificate authorization.

Keep the same private release keystore for updates. Debug-signed and
tester-signed APKs cannot update each other in place despite their shared app ID.
**Do not uninstall an existing vault to switch build types**: that can destroy
local data. Use a separate test device for different signing keys.

If release signing is unavailable, an optimized local experiment can explicitly
opt in using `--android-project-arg=allowDebugSigning=true`. This does not change
the normal release signing policy. Such an APK is **debug-signed, test-only and
must never be distributed**, even though its filename says `release`.

## Behavior and charges

- Internet and data SMS appear together in one chronological chat history.
  Selection changes the sending transport, not the conversation.
- Data SMS supports encrypted text only. Attachments, reactions, editing, remote
  deletion, and replies are internet-only. Copy and local deletion remain available.
- Cellular SMS service is required on both ends; mobile data and Wi-Fi are not.
  With no cellular coverage, receipt depends on the carrier's store-and-forward
  service and expiry. Data SMS is not Bluetooth or satellite messaging.
- The counter shows `characters/SMS segments`, with a maximum of 10 segments.
  V2 carries a 1-byte version, 6-byte authenticated timestamp and AES-GCM
  nonce/tag (34 bytes of framing/security overhead, plus the 1-byte version).
  With the current 112-byte application payload per segment, up to 77 single-byte
  ASCII characters fit in one segment. Unicode text uses UTF-8 bytes, so it may
  fit fewer visible characters. Binary ciphertext is sent without Base64
  expansion; ordinary 160-character text-SMS limits do not apply. The count is
  the number of binary SMS submissions, not a carrier billing guarantee. Each
  segment may be charged.
- Compact V2 messages are routed by the sender's phone number to a saved,
  linked conversation and encrypted with that conversation's existing E2EE key.
  Both people must have established that encrypted conversation online first.
  Unknown or ambiguous phone numbers are not imported or shown as new chats.
  Legacy V1 messages remain readable. A shared application-wide key is not used:
  a key shipped with every install could be extracted and would not provide
  confidentiality from anyone who obtains the app.
- Bubble colors and a **Data SMS** label identify the transport. **Device
  delivered** means every segment has a successful carrier delivery report,
  not that the app decrypted it or that a person read it. Missing reports remain
  unconfirmed. No SMS read receipts or app acknowledgements are automatically sent.
- There is no automatic resend or silent fallback. After a partial or uncertain
  submission, check before sending again to avoid duplicate charges.
- Port-addressed SMS normally bypasses the regular SMS inbox. A port does not
  uniquely identify or authenticate an app; authenticated encryption protects
  the content. Carrier and device support varies.
- Native receivers retain ciphertext while Flutter is absent or the vault is
  locked. Import and chat notifications occur when the authorized chat session
  is open and unlocked. No plaintext or key is supplied to the receiver. Android
  force-stop, permission revocation, app removal, or OEM restrictions can prevent
  receipt. Native queues are bounded to 100 incoming assemblies and 100 outgoing
  status records separately; a full queue rejects new work. Queued parts/statuses
  expire after seven days, cleaned up on queue operations. Fully delivered
  outgoing records are also removed after their status is saved in chat.

## Real-device verification

Before relying on this feature, test both directions on two supported phones
with Wi-Fi and mobile data off but cellular SMS service active. Check the usual
SMS inboxes, counts, carrier delivery reports, restart/background receipt, unlock
import, wrong numbers, permission denial, and dual-SIM behavior. Emulator/unit
tests do not establish carrier compatibility or guarantee inbox exclusion.
