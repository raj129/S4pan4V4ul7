# Chat ring requests

Ring requests are explicit events sent from a chat; ordinary message alerts are
unchanged. A request appears in the conversation with its timestamp and
standard sent/delivered/read status. Delivery means the recipient's device
acknowledged the event, not that Android confirms sound or vibration played.
Send a request from the chat's overflow menu; the lock-vault action remains in
the app bar.

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
