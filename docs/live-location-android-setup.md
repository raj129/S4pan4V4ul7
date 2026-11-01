# Android live-location setup

Live-location sharing is Android-only. It requires location and notification permissions, runs a location foreground service while sharing, and posts one encrypted marker message. Coordinate updates are written to the thread's `live_locations` subcollection and encrypted with the existing thread key.

## Google Maps API key

1. In Google Cloud, enable **Maps SDK for Android** and configure billing for the Firebase/Google Cloud project. Maps Platform pricing is subject to current Google terms and usage.
2. Create an Android-restricted Maps API key. Restrict it to this app's package (`com.system.calculator`) and the SHA-1 fingerprints of the release/tester keystore and the debug keystore (see [Signing fingerprints](firebase-github-actions.md#signing-fingerprints)). Add the same fingerprints to the Firebase Android app and re-download `google-services.json`.
3. Put the key in `GOOGLE_MAPS_ANDROID_API_KEY` in the shared local `.api_keys.json` file. The file is Git-ignored and also holds the GIPHY API key; see [Chat GIFs and stickers](chat-gif-stickers.md) for setup.
4. The IntelliJ `main.dart` run configuration and local CLI builds use `.api_keys.json` with `--dart-define-from-file`; Android Gradle reads the same file for the Maps manifest placeholder. CI should create that file from protected secrets during the build, without logging it.

Without a key, the feature remains buildable but the map screen explains that Google Maps is not configured.

## User permissions and behavior

The user chooses a 15-minute, 1-hour, or 8-hour session. The app requests location access and notification permission before starting. To keep sharing active when the app is backgrounded, Android must grant **Allow all the time** location access and display the ongoing foreground-service notification. Users can stop sharing from the message card or map screen; sessions also stop at expiry.

The sharing action and map are intentionally unavailable on Windows. The Windows chat shows an Android-availability notice for received live-location messages.

## Pins, routes and arrival alerts

- **Pin / Route** (attach sheet, or type `/pin`): drop a pin or choose a start and destination. The payload is encrypted as the message body. Routes are drawn from the Google Routes API using `GOOGLE_MAPS_ANDROID_API_KEY`; enable the Routes API on that key. Without it a route is a straight line.
- **Place search** (Android only): the map picker shows a search box when the map is configured. It uses `GOOGLE_MAPS_ANDROID_API_KEY`; enable the Places API (New) on that key.
- **Key security:** this key ships inside the APK. Remove its Android app restriction only if you accept that, and restrict it to Maps SDK for Android, Routes API, and Places API (New), with quotas and a budget alert.
- **Arrival alert** (attach sheet, or type `/arrive`): add several places for the current chat. When the device comes within 100 m of a place, an encrypted "I have reached <place>" message is sent once to the chat partner. Alerts are stored in secure storage on the device, run while the location foreground service is allowed (**Allow all the time** recommended), and are cleared on sign-out.
- Any of these messages, including live locations, can be replied to by swiping or from the long-press menu.
