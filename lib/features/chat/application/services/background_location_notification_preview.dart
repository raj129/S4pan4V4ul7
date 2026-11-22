import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class BackgroundLocationNotificationPreview {
  BackgroundLocationNotificationPreview._();

  static const _channelId = 'background_location_preview';
  static const _channelName = 'Background location preview';
  static const _notificationId = 214;

  static Future<void> show({
    required String title,
    required String body,
  }) async {
    if (!Platform.isAndroid) return;
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: 'One-off test notifications for background location.',
        importance: Importance.high,
        playSound: false,
        enableVibration: false,
      ),
    );
    await notifications.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription:
              'One-off test notifications for background location.',
          importance: Importance.high,
          priority: Priority.high,
          playSound: false,
          enableVibration: false,
        ),
      ),
    );
  }
}
