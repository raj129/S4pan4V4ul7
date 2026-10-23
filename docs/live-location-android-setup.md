# Android live-location setup

Live-location sharing is Android-only. It requires location and notification permissions, runs a location foreground service while sharing, and posts one encrypted marker message. Coordinate updates are written to the thread's `live_locations` subcollection and encrypted with the existing thread key.

## Google Maps API key

1. In Google Cloud, enable **Maps SDK for Android** and configure billing for the Firebase/Google Cloud project. Maps Platform pricing is subject to current Google terms and usage.
2. Create an Android-restricted Maps API key. Restrict it to this app's package (`com.system.calculator`) and the signing certificate fingerprints for each build channel.
3. Add the key as the GitHub Actions secret `GOOGLE_MAPS_ANDROID_API_KEY` so release builds display maps. CI injects it through the Android manifest placeholder and a Dart define; it is not stored in source control.
4. For local Android builds, copy `android/google_maps_key.json.example` to `android/google_maps_key.json` and put the key in the JSON value. The real file is Git-ignored. The IntelliJ `main.dart` run configuration passes it to Flutter with `--dart-define-from-file`, and Gradle reads the same file for the Android manifest placeholder. Local CLI runs can use `flutter run --dart-define-from-file=android/google_maps_key.json`.

Without a key, the feature remains buildable but the map screen explains that Google Maps is not configured.

## User permissions and behavior

The user chooses a 15-minute, 1-hour, or 8-hour session. The app requests location access and notification permission before starting. To keep sharing active when the app is backgrounded, Android must grant **Allow all the time** location access and display the ongoing foreground-service notification. Users can stop sharing from the message card or map screen; sessions also stop at expiry.

The sharing action and map are intentionally unavailable on Windows. The Windows chat shows an Android-availability notice for received live-location messages.
