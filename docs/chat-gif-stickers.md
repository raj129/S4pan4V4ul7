# Chat GIFs and stickers

## Get a GIPHY API key

1. Sign in or create an account at [developers.giphy.com](https://developers.giphy.com/).
2. Open the developer dashboard and create an app for the GIPHY API.
3. Copy the API key shown for that app.
4. Put the key in `GIPHY_API_KEY` in your local `.api_keys.json` file. Do not
   paste it into source code or commit that file.

New GIPHY API keys start with a beta limit of 100 API calls per hour. GIPHY's
dashboard explains how to request a production key if the integration needs a
higher limit.

## Use the shared local key file

The repository contains `.api_keys.json.example` with the required fields.
Copy it to `.api_keys.json` and fill in both `GOOGLE_MAPS_ANDROID_API_KEY` and
`GIPHY_API_KEY`. The real file is Git-ignored. The same file supplies the Maps
key to Android Gradle and both values to Flutter's compile-time defines:

```powershell
flutter run --dart-define-from-file=.api_keys.json
flutter build apk --dart-define-from-file=.api_keys.json
```

For CI, create `.api_keys.json` during the build from your CI secret store and
pass it to the same Flutter command; never print the generated file in logs.
GIPHY requires Search and Trending requests to be made from the client, so the
GIPHY key is included in the compiled app. Use a key intended for this
integration and follow GIPHY's API terms.

The composer has Emoji, Stickers, and GIF tabs with one shared search field.
Emoji queries match emoji names/keywords; sticker and GIF queries go to the
selected GIPHY endpoint; My stickers searches the local pack. Remote requests
are debounced, use the `g` content rating, fetch at most 24 results per page,
and load no more than five pages. Small still images are used in the grid; full
media downloads are deferred until selection and capped at 4 MB.

Outgoing GIFs and stickers use the existing end-to-end encrypted chat media
path. Personal sticker packs remain local to the device and signed-in account,
encrypted at rest with a key held in platform secure storage, and capped at
100 items / 32 MB total.
