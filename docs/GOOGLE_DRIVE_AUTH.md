# Persistent Google Drive authorization

The app requests Drive access only when a user first starts or restores a Drive
backup. Google access tokens remain short-lived; Firebase Functions exchanges
the initial server authorization code and refreshes access tokens without
reopening the Google consent flow. Refresh tokens are encrypted before being
stored in the server-only `googleDriveAuthTokens` collection. They are never
stored on the device.

## One-time deployment setup

1. In Google Cloud Console, use the same OAuth web client as
   `googleServerClientId` in `lib/features/chat/di/chat_dependencies.dart`.
   Set its client secret in Firebase Functions Secret Manager; do not put it in
   source control:

   ```powershell
   firebase functions:secrets:set GOOGLE_OAUTH_CLIENT_SECRET
   ```

2. Generate a random 32-byte encryption key and store its base64 value as a
   Firebase Functions secret:

   ```powershell
   node -p "require('node:crypto').randomBytes(32).toString('base64')"
   firebase functions:secrets:set GOOGLE_DRIVE_TOKEN_ENCRYPTION_KEY
   ```

   Keep this key stable. Changing it requires re-encrypting existing refresh
   tokens before the old key is discarded.

3. Deploy the Functions:

   ```powershell
   firebase deploy --only functions
   ```

The Google OAuth consent screen must include the Drive app-data scope. If an
account already authorized this app without offline access, revoke the existing
grant in Google Account security settings, then connect Drive again.
