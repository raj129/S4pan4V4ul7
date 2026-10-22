# Firebase GitHub Actions setup

The `Flutter CI` workflow validates Firebase backend changes on pull requests and deploys the configured Firebase resources from `main`.

## Workflow behavior

- Pull requests run Flutter analysis/tests, build Cloud Functions, and execute Firestore/Storage security-rule tests against local Firebase emulators. They never authenticate to or deploy to the production Firebase project.
- Pushes to `main` deploy Firestore rules, Storage rules, and Cloud Functions after all validation jobs pass. The Android App Distribution release runs after that deployment succeeds.
- `workflow_dispatch` can run the workflow manually. Production deploy jobs run only when the selected ref is `main`.
- The deployment uses the project ID in `firebase.json` and keeps the Firestore database ID `default1`.

## Required GitHub configuration

Set these repository **Actions variables**:

| Variable | Value |
| --- | --- |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Full Google Cloud Workload Identity Provider resource name, such as `projects/PROJECT_NUMBER/locations/global/workloadIdentityPools/POOL_ID/providers/PROVIDER_ID` |
| `GCP_FIREBASE_DEPLOY_SERVICE_ACCOUNT` | Email address of the dedicated Google Cloud service account used by the workflow |
| `FIREBASE_TESTER_GROUPS` | Firebase App Distribution tester group alias |

The existing Android distribution job also needs these **Actions secrets**:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

After the OIDC setup is verified, the old `FIREBASE_SERVICE_ACCOUNT_JSON` secret is no longer used by this workflow and can be removed.

## Google Cloud setup

1. Enable the Google Cloud Workload Identity Federation APIs and create a workload identity pool and OIDC provider for GitHub Actions.
2. Configure the provider to trust only this repository (`raj129/shadow4726262`) and restrict production deployment to the `refs/heads/main` ref.
3. Create a dedicated service account and grant the provider's principal set permission to impersonate it.
4. Grant that account only the permissions required to deploy Cloud Functions, release Firestore and Storage rules, and upload Android builds to Firebase App Distribution. Cloud Functions deployment may also require service-account impersonation and permissions for its configured runtime/build resources.
5. Add the provider resource name and service-account email to the GitHub Actions variables listed above.

Do not grant GitHub Actions access to production credentials from pull-request events. The deploy jobs are gated to `main`; rule tests use the local emulators and a demo project ID.
