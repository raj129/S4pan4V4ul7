# Android live-location setup

Live-location sharing is Android-only. It requires location and notification permissions, runs a location foreground service while sharing, and posts one encrypted marker message. Coordinate updates are written to the thread's `live_locations` subcollection and encrypted with the existing thread key.

## Google Maps API key

1. In Google Cloud, enable **Maps SDK for Android** and configure billing for the Firebase/Google Cloud project. Maps Platform pricing is subject to current Google terms and usage.
2. Create an Android-restricted Maps API key. Restrict it to this app's package (`com.system.calculator`) and the signing certificate fingerprints for each build channel.
3. Put the key in `GOOGLE_MAPS_ANDROID_API_KEY` in the shared local `.api_keys.json` file. The file is Git-ignored and also holds the GIPHY API key; see [Chat GIFs and stickers](chat-gif-stickers.md) for setup.
4. The IntelliJ `main.dart` run configuration and local CLI builds use `.api_keys.json` with `--dart-define-from-file`; Android Gradle reads the same file for the Maps manifest placeholder. CI should create that file from protected secrets during the build, without logging it.

Without a key, the feature remains buildable but the map screen explains that Google Maps is not configured.

## User permissions and behavior

The user chooses a 15-minute, 1-hour, or 8-hour session. The app requests location access and notification permission before starting. To keep sharing active when the app is backgrounded, Android must grant **Allow all the time** location access and display the ongoing foreground-service notification. Users can stop sharing from the message card or map screen; sessions also stop at expiry.

The sharing action and map are intentionally unavailable on Windows. The Windows chat shows an Android-availability notice for received live-location messages.
