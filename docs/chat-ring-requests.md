# Chat ring requests

Ring requests are explicit events sent from a chat. A request appears in the
conversation with its timestamp and
standard sent/delivered/read status. Delivery means the recipient's device
acknowledged the event, not that Android confirms sound or vibration played.
Send a request from the chat's overflow menu; the lock-vault action remains in
the app bar.

Ring-request and incoming-chat notification settings are managed from
**Settings → Notification settings**. Choose a notification type to open its
configuration. Each type has independent alert and notification text settings.
Chat tests and incoming chat alerts use the recipient's saved header/body and
never display the sender's message content.
On Android, recipients can enable or disable incoming ring requests and choose
**Follow system** (the default) or **Use app settings**. In Follow system mode,
the app uses the phone's default ringtone, vibration mode, and Android's camera
flash-notification setting where available. The system ringtone and flash
settings can be changed from the displayed system-settings shortcuts. In Use
app settings mode, Ring, Vibrate, and Flashlight are independent switches, so
ring + vibration, either alone, flashlight-only, or silent are possible. App
ring/vibration choices override the phone's ringer mode, but Do Not Disturb and
Android/device restrictions still apply.

In Use app settings mode, recipients can select a ringtone, one of three
vibration presets, and an alert timeout from 5 to 120 seconds (5 seconds by
default). The app flashlight switch is off by default and has slow, double,
and fast blink presets. Camera permission and a hardware flash are required.
Android 14 and later do not allow a camera foreground service to start from a
background FCM event, so app-controlled flashlight blinking cannot be promised
for locked/background requests on those versions. Follow system mode instead
reads Android's camera-flash notification setting and uses the system-selected
behavior when permission, hardware, and Android background rules permit it.

Incoming chat alerts in **Follow system** use Android's standard notification
sound, vibration, and accessibility flash settings on a dedicated high-
importance notification channel. In **Use app settings** mode, chat-message
alerts use a silent notification channel while the selected Android notification
sound, app vibration pattern, and flashlight are driven separately by the
native alert service. Chat's app-settings sound picker selects notification
tones, while ring requests continue using the phone ringtone picker. Android
does not expose a global vibration-pattern picker; Follow system delegates
pattern selection to the notification channel, and app settings offer
standard/short/long patterns. Ring requests continue using their own repeating
native alert service. Both modes post a
regular notification that Android can bridge to Wear OS; watch delivery and
alerting remain subject to phone/watch notification settings and OS policies.
For app-configured chat alerts, the selected vibration pattern plays once per
message; ring-request vibration continues repeating until timeout.

The ring service's required foreground-service notification is marked
phone-local so Wear OS receives the regular user-facing notification rather
than a second service notification. The repository has no separate Wear OS app;
watch delivery uses Android's notification bridge.

The background-location notification body defaults to empty but remains
editable. Its settings test shows a one-off preview and does not start live
location sharing.

The settings test alert has a separate delay selector (0, 3, 5, 10, or 15
seconds; default 0). The delay affects only the test, not incoming requests.
Incoming alerts repeat until the timeout or until the recipient presses
**Silence** in the system notification. While an alert is active, the service
temporarily routes remote volume-key adjustments and listens for system volume
changes; either event stops ring, vibration, and flashlight output. Android or
an active media/call session can still claim the hardware keys first, so volume
silencing is best-effort. The power button only locks the screen and is not
delivered to ordinary apps as a silence command; use **Silence** or wait for
the 5-second default timeout.

When enabled, the alert uses an Android foreground service and the required
temporary foreground-service notification. It contains no custom title or
message and is removed when the alert is silenced or times out. Android still
shows the app's system identity; a fully invisible foreground-service
notification is not supported. The notification uses the calculator app icon.
Android requires a small app icon for notifications and does not allow the app
to replace it with a profile photo. The app does not open a screen or full-screen
intent. Android's
notification permission, lock-screen privacy settings, Do Not Disturb, battery
restrictions, and OEM policies can affect whether an alert is visible or
audible. A selected ringtone URI may not identify the same sound on every
device; unavailable URIs fall back to the device's default ringtone. App
settings use the app-selected output even when the phone is set to vibrate or
silent, but Do Not Disturb and Android policy can still suppress it.
