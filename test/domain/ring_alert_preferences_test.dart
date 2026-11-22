import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/domain/entities/ring_alert_preferences.dart';

void main() {
  test(
    'defaults to enabled system mode, no flashlight, and zero test delay',
    () {
      const preferences = RingAlertPreferences();

      expect(preferences.enabled, isTrue);
      expect(preferences.source, RingAlertSource.system);
      expect(preferences.mode, RingAlertMode.ringAndVibrate);
      expect(preferences.timeoutSeconds, 5);
      expect(RingAlertPreferences.timeoutOptionsSeconds, [
        5,
        10,
        15,
        30,
        45,
        60,
        90,
        120,
      ]);
      expect(preferences.flashlightEnabled, isFalse);
      expect(preferences.testDelaySeconds, 0);
      expect(
        preferences.notificationTitle,
        RingAlertPreferences.defaultNotificationTitle,
      );
      expect(
        preferences.notificationBody,
        RingAlertPreferences.defaultNotificationBody,
      );
      expect(preferences.notificationTitle, isEmpty);
      expect(preferences.notificationBody, isEmpty);
    },
  );

  test('round-trips combined alert mode and custom patterns', () {
    const preferences = RingAlertPreferences(
      enabled: false,
      source: RingAlertSource.custom,
      ringSoundEnabled: true,
      vibrationEnabled: true,
      ringtoneUri: 'content://settings/system/ringtone',
      timeoutSeconds: 60,
      vibrationPattern: RingVibrationPattern.shortPulses,
      flashlightEnabled: true,
      flashPattern: RingFlashPattern.doubleBlink,
      testDelaySeconds: 10,
      notificationTitle: 'Personal ring',
      notificationBody: 'Ring my phone',
    );

    expect(
      RingAlertPreferences.fromFirestore(preferences.toFirestore()),
      preferences,
    );
  });

  test('invalid mode and timeout safely use supported defaults', () {
    final preferences = RingAlertPreferences.fromFirestore({
      'enabled': false,
      'mode': 'unexpected',
      'timeoutSeconds': 999,
    });

    expect(preferences.enabled, isFalse);
    expect(preferences.mode, RingAlertMode.ringAndVibrate);
    expect(preferences.timeoutSeconds, 5);
    expect(preferences.testDelaySeconds, 0);
    expect(preferences.flashlightEnabled, isFalse);
  });

  test('preserves previous explicit mode settings as custom mode', () {
    final preferences = RingAlertPreferences.fromFirestore({
      'enabled': true,
      'mode': 'ringtone',
    });

    expect(preferences.source, RingAlertSource.custom);
    expect(preferences.mode, RingAlertMode.ringtone);
    expect(preferences.ringSoundEnabled, isTrue);
    expect(preferences.vibrationEnabled, isFalse);
  });

  test('migrates previous mode values to independent toggles', () {
    final oldVibrate = RingAlertPreferences.fromFirestore({'mode': 'vibrate'});
    final oldSilent = RingAlertPreferences.fromFirestore({'mode': 'silent'});

    expect(oldVibrate.ringSoundEnabled, isFalse);
    expect(oldVibrate.vibrationEnabled, isTrue);
    expect(oldSilent.ringSoundEnabled, isFalse);
    expect(oldSilent.vibrationEnabled, isFalse);
  });

  test('clears only the old automatic ring notification text', () {
    final oldDefaults = RingAlertPreferences.fromFirestore({
      'notificationTitle': RingAlertPreferences.legacyDefaultNotificationTitle,
      'notificationBody': RingAlertPreferences.legacyDefaultNotificationBody,
    });
    final customText = RingAlertPreferences.fromFirestore({
      'notificationTitle': 'My ring header',
      'notificationBody': 'My ring text',
    });

    expect(oldDefaults.notificationTitle, isEmpty);
    expect(oldDefaults.notificationBody, isEmpty);
    expect(customText.notificationTitle, 'My ring header');
    expect(customText.notificationBody, 'My ring text');
  });

  test('clears only the old automatic ring notification text', () {
    final oldDefaults = RingAlertPreferences.fromFirestore({
      'notificationTitle': RingAlertPreferences.legacyDefaultNotificationTitle,
      'notificationBody': RingAlertPreferences.legacyDefaultNotificationBody,
    });
    final customText = RingAlertPreferences.fromFirestore({
      'notificationTitle': 'My ring header',
      'notificationBody': 'My ring text',
    });

    expect(oldDefaults.notificationTitle, isEmpty);
    expect(oldDefaults.notificationBody, isEmpty);
    expect(customText.notificationTitle, 'My ring header');
    expect(customText.notificationBody, 'My ring text');
  });
}
