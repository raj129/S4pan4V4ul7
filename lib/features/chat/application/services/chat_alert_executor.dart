import 'dart:io';

import 'package:android_ring_alerts/android_ring_alerts.dart';
import 'package:photo_vault/features/vault/domain/entities/incoming_chat_alert_preferences.dart';

Future<void> startIncomingChatAlert({
  required String alertId,
  required IncomingChatAlertPreferences preferences,
  required bool allowFlashInBackground,
}) async {
  if (!Platform.isAndroid ||
      preferences.source == NotificationAlertSource.system) {
    return;
  }
  if (preferences.source == NotificationAlertSource.custom &&
      !preferences.ringSoundEnabled &&
      !preferences.vibrationEnabled &&
      !preferences.flashlightEnabled) {
    return;
  }
  await AndroidRingAlerts.startAlert(
    alertId: alertId,
    source: preferences.source.name,
    ringSoundEnabled: preferences.ringSoundEnabled,
    vibrationEnabled: preferences.vibrationEnabled,
    timeoutSeconds: 5,
    title: 'New chat message',
    body: 'A new message is waiting.',
    ringtoneUri: preferences.notificationSoundUri,
    vibrationPattern: preferences.vibrationPattern.name,
    flashlightEnabled: preferences.flashlightEnabled,
    flashPattern: 'slowBlink',
    allowFlashInBackground: allowFlashInBackground,
    notificationAudioUsage: true,
    repeatVibration: false,
  );
}
