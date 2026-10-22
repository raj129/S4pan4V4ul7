# Firebase GitHub Actions setup

The `Flutter CI` workflow validates Firebase backend changes on pull requests and deploys the configured Firebase resources from `main`.

## Workflow behavior

- Pull requests run Flutter analysis/tests, build Cloud Functions, and execute Firestore/Storage security-rule tests against local Firebase emulators. They never authenticate to or deploy to the production Firebase project.
- Pushes to `main` deploy Firestore rules, Storage rules, and Cloud Functions after all validation jobs pass. The Android App Distribution release runs after that deployment succeeds.
- `workflow_dispatch` can run the workflow manually. Production deploy jobs run only when the selected ref is `main`.
- The deployment uses the project ID in `firebase.json` and keeps the Firestore database ID `default1`.

## Required GitHub configuration

Set this repository **Actions variable**:

| Variable | Value |
| --- | --- |
| `FIREBASE_TESTER_GROUPS` | Firebase App Distribution tester group alias |

Both Firebase authentication steps use the **Actions secret** `FIREBASE_SERVICE_ACCOUNT_JSON`. Its value must be the complete JSON key contents for the Google Cloud service account used for Firebase deployment and App Distribution. The workflow checks for this secret before invoking the auth action.

The Android release job also needs these **Actions secrets**:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`
- `GOOGLE_MAPS_ANDROID_API_KEY`

Do not put the JSON key in the repository or workflow YAML. Rotate the key if it is exposed, and grant its service account only the permissions required by the Firebase resources being deployed.

## Google Cloud service account setup

1. Create or select a dedicated Google Cloud service account for this repository.
2. Grant it the Firebase/IAM permissions needed to deploy Cloud Functions, release Firestore and Storage rules, and upload Android builds to Firebase App Distribution. Cloud Functions deployment may also require service-account impersonation and permissions for its configured runtime/build resources.
3. Create a JSON key for that service account, then copy its complete JSON contents into the GitHub Actions secret `FIREBASE_SERVICE_ACCOUNT_JSON`.
4. Keep the key out of source control and rotate it periodically.

The deploy and distribution jobs run only on `main`; pull requests use local Firebase emulators and do not access the production service-account secret.
