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

### Cloud Storage API 403 during deployment

If deployment fails with an error like:

```text
storage: ensuring required API firebasestorage.googleapis.com is enabled...
403 Permission denied to get service [firebasestorage.googleapis.com]
```

the service account can authenticate, but cannot query the API's enablement state through Google Cloud Service Usage. This is separate from the Storage rules and from the roles used to deploy rules.

Use the least-privilege setup:

1. Have a project owner or administrator enable **Cloud Storage for Firebase API** (`firebasestorage.googleapis.com`) once for project `shadow4726262`. In Google Cloud Console, choose that project, open **APIs & Services → Library**, search for the API, then select **Enable**. Alternatively, an administrator can run:

   ```sh
   gcloud services enable firebasestorage.googleapis.com --project=shadow4726262
   ```

2. Grant the deployment service account **Service Usage Viewer** (`roles/serviceusage.serviceUsageViewer`) on project `shadow4726262`. It allows the Firebase CLI to inspect service enablement status without granting permission to enable APIs.
3. Check that the other APIs required by the configured Firebase products and Cloud Functions runtime are enabled as well. Enable any missing APIs administratively, not from this CI identity.
4. Rerun the workflow on `main`.

The Firebase CLI derives the deploy project ID from `firebase.json`; no separate project-ID secret or variable is needed. Updating IAM roles does **not** require regenerating or replacing `FIREBASE_SERVICE_ACCOUNT_JSON`. Only replace that secret if the service-account key itself was rotated or revoked.

The deploy and distribution jobs run only on `main`; pull requests use local Firebase emulators and do not access the production service-account secret.
