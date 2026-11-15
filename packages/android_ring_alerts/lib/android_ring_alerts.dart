import 'dart:io';

import 'package:flutter/services.dart';

class AndroidRingAlerts {
  AndroidRingAlerts._();

  static const _channel = MethodChannel('com.system.calculator/ring_alerts');

  static Future<String?> pickRingtone({String? currentUri}) async {
    if (!Platform.isAndroid) return null;
    return _channel.invokeMethod<String>('pickRingtone', {
      'currentUri': ?currentUri,
    });
  }

  static Future<String?> ringtoneTitle(String? uri) async {
    if (!Platform.isAndroid || uri == null) return null;
    return _channel.invokeMethod<String>('ringtoneTitle', {'uri': uri});
  }

  static Future<bool> hasFlashlight() async {
    if (!Platform.isAndroid) return false;
    return await _channel.invokeMethod<bool>('hasFlashlight') ?? false;
  }

  static Future<Map<String, Object?>> systemAlertSettings() async {
    if (!Platform.isAndroid) return const {};
    final result = await _channel.invokeMapMethod<String, Object?>(
      'systemAlertSettings',
    );
    return result ?? const {};
  }

  static Future<void> openSystemRingtoneSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openSystemRingtoneSettings');
  }

  static Future<void> openSystemFlashSettings() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('openSystemFlashSettings');
  }

  static Future<void> startAlert({
    required String alertId,
    required String source,
    required bool ringSoundEnabled,
    required bool vibrationEnabled,
    required int timeoutSeconds,
    required String title,
    required String body,
    required String vibrationPattern,
    required bool flashlightEnabled,
    required String flashPattern,
    int startDelaySeconds = 0,
    bool allowFlashInBackground = false,
    String? ringtoneUri,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('startAlert', {
      'alertId': alertId,
      'source': source,
      'ringSoundEnabled': ringSoundEnabled,
      'vibrationEnabled': vibrationEnabled,
      'timeoutSeconds': timeoutSeconds,
      'title': title,
      'body': body,
      'vibrationPattern': vibrationPattern,
      'flashlightEnabled': flashlightEnabled,
      'flashPattern': flashPattern,
      'startDelaySeconds': startDelaySeconds,
      'allowFlashInBackground': allowFlashInBackground,
      'ringtoneUri': ?ringtoneUri,
    });
  }

  static Future<void> stopAlert({String? alertId}) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod<void>('stopAlert', {'alertId': ?alertId});
  }
}
