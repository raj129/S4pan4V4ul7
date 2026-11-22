import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:android_ring_alerts/android_ring_alerts.dart';

import '../../domain/repositories/message_repository.dart';
import '../../domain/entities/ring_alert_preferences.dart';
import 'package:photo_vault/firebase_options.dart';
import '../../domain/repositories/push_token_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_keys.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/features/vault/domain/entities/incoming_chat_alert_preferences.dart';
import 'chat_notification_service.dart';
import 'chat_backup_scheduler.dart';
import 'chat_alert_executor.dart';

String? _ringtoneUri(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return raw;
}

String _ringString(Object? raw, String fallback) =>
    raw is String ? raw : fallback;

bool _ringBool(Object? raw, bool fallback) => raw == 'true'
    ? true
    : raw == 'false'
    ? false
    : fallback;

({bool ring, bool vibrate}) _legacyRingToggles(String mode) => (
  ring: mode == 'ringAndVibrate' || mode == 'ringtone',
  vibrate: mode == 'ringAndVibrate' || mode == 'vibrate',
);

@pragma('vm:entry-point')
Future<void> handleChatPushInBackground(RemoteMessage message) async {
  // The background isolate may be reused between messages; a second
  // initializeApp for the default app throws.
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 20));
  }

  final Object? rawThreadId = message.data['threadId'];
  final Object? rawMessageId = message.data['messageId'];
  if (rawThreadId is! String || rawThreadId.isEmpty) return;
  final threadId = rawThreadId;
  final messageId = rawMessageId is String ? rawMessageId : null;

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
  final androidNotifications = notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await ChatNotificationService.createAndroidNotificationChannels(
    androidNotifications,
  );

  if (message.data['eventType'] == 'ringRequest') {
    final source = message.data['ringSource'] == 'custom' ? 'custom' : 'system';
    final oldMode = _ringString(message.data['ringMode'], 'ringAndVibrate');
    final oldToggles = _legacyRingToggles(oldMode);
    final ringSoundEnabled = _ringBool(
      message.data['ringSoundEnabled'],
      oldToggles.ring,
    );
    final vibrationEnabled = _ringBool(
      message.data['vibrationEnabled'],
      oldToggles.vibrate,
    );
    final flashlightEnabled = message.data['ringFlashlightEnabled'] == 'true';
    final ringEnabled = message.data['ringEnabled'] != 'false';
    if (ringEnabled &&
        (source == 'system' ||
            ringSoundEnabled ||
            vibrationEnabled ||
            flashlightEnabled)) {
      try {
        await AndroidRingAlerts.startAlert(
          alertId: messageId ?? threadId,
          source: source,
          ringSoundEnabled: ringSoundEnabled,
          vibrationEnabled: vibrationEnabled,
          timeoutSeconds:
              int.tryParse(message.data['ringTimeoutSeconds'] ?? '') ?? 5,
          title: _ringString(
            message.data['ringTitle'],
            RingAlertPreferences.defaultNotificationTitle,
          ),
          body: _ringString(
            message.data['ringBody'],
            RingAlertPreferences.defaultNotificationBody,
          ),
          ringtoneUri: _ringtoneUri(message.data['ringtoneUri']),
          vibrationPattern: _ringString(
            message.data['ringVibrationPattern'],
            'standard',
          ),
          flashlightEnabled: flashlightEnabled,
          flashPattern: _ringString(
            message.data['ringFlashPattern'],
            'slowBlink',
          ),
          allowFlashInBackground: false,
        );
      } catch (error) {
        debugPrint('Could not start incoming ring request alert: $error');
      }
    }
    if (ringEnabled) {
      final ringPreferences = IncomingChatAlertPreferences(
        source: source == 'custom'
            ? NotificationAlertSource.custom
            : NotificationAlertSource.system,
        vibrationEnabled: vibrationEnabled,
      );
      await notifications.show(
        id: 2,
        title: _ringString(
          message.data['ringTitle'],
          RingAlertPreferences.defaultNotificationTitle,
        ),
        body: _ringString(
          message.data['ringBody'],
          RingAlertPreferences.defaultNotificationBody,
        ),
        notificationDetails: ChatNotificationService.notificationDetailsFor(
          tag: 'ring-${messageId ?? threadId}',
          preferences: ringPreferences,
        ),
        payload: threadId,
      );
    }
  } else if (message.data['notify'] != 'false') {
    var alertTitle = SettingsRepository.defaultIncomingChatAlertTitle;
    var alertBody = SettingsRepository.defaultIncomingChatAlertText;
    try {
      const secureStorage = FlutterSecureStorage();
      final configuredTitle = await secureStorage.read(
        key: StorageKeys.incomingChatAlertTitle,
      );
      if (configuredTitle != null) {
        alertTitle = configuredTitle.trim();
      }
      final configured = await secureStorage.read(
        key: StorageKeys.incomingChatAlertText,
      );
      if (configured != null) {
        alertBody = configured.trim();
      }
    } catch (error) {
      debugPrint('Could not read custom notification settings: $error');
    }
    var alertPreferences = const IncomingChatAlertPreferences();
    try {
      final rawPreferences = await const FlutterSecureStorage().read(
        key: StorageKeys.incomingChatAlertPreferences,
      );
      if (rawPreferences != null) {
        alertPreferences = IncomingChatAlertPreferences.fromJson(
          jsonDecode(rawPreferences),
        );
      }
    } catch (error) {
      debugPrint('Could not read chat alert preferences: $error');
    }
    await notifications.show(
      id: 0,
      title: alertTitle,
      body: alertBody,
      notificationDetails: ChatNotificationService.notificationDetailsFor(
        preferences: alertPreferences,
        tag: threadId,
      ),
      payload: threadId,
    );
    try {
      await startIncomingChatAlert(
        alertId: messageId ?? threadId,
        preferences: alertPreferences,
        allowFlashInBackground: false,
      );
    } catch (error) {
      debugPrint('Could not start incoming chat alert: $error');
    }
  }

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || messageId == null || messageId.isEmpty) return;
  await scheduleChatReceive(uid: uid, threadId: threadId, messageId: messageId);
}

/// Registers this device for FCM pushes sent by the `onChatMessageCreated`
/// Cloud Function, and routes notification taps to the right conversation.
///
/// Pushes are data-only so the background handler can acknowledge delivery.
/// It displays a generic local notification without exposing message content.
class PushNotificationService {
  PushNotificationService({
    required PushTokenRepository tokenRepository,
    required ChatNotificationService notificationService,
    required MessageRepository messageRepository,
    FirebaseMessaging? messaging,
  }) : _tokens = tokenRepository,
       _notifications = notificationService,
       _messagingOverride = messaging;

  final PushTokenRepository _tokens;
  final ChatNotificationService _notifications;
  final FirebaseMessaging? _messagingOverride;

  FirebaseMessaging get _messaging =>
      _messagingOverride ?? FirebaseMessaging.instance;

  String? _uid;
  String? _token;
  StreamSubscription<String>? _refreshSub;
  StreamSubscription<RemoteMessage>? _openedSub;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  bool _tapHandlersAttached = false;

  /// Register the device for [uid]. Safe to call repeatedly.
  Future<void> start(String uid) async {
    if (_uid == uid && _token != null) return;
    _uid = uid;
    try {
      await _attachTapHandlers();
      await _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen(
        _handleForegroundMessage,
      );
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null) await _store(uid, token);
      await _refreshSub?.cancel();
      _refreshSub = _messaging.onTokenRefresh.listen((fresh) {
        final current = _uid;
        if (current == null) return;
        final stale = _token;
        unawaited(
          () async {
            if (stale != null && stale != fresh) {
              await _tokens.deleteToken(uid: current, token: stale);
            }
            await _store(current, fresh);
          }().catchError((_) {}),
        );
      });
    } catch (_) {
      // Push is an enhancement; chat must keep working without Play Services
      // or when Firebase Messaging is unavailable (e.g. tests, desktop).
    }
  }

  /// Unregister on sign-out so the previous account stops receiving alerts.
  Future<void> stop() async {
    final uid = _uid;
    final token = _token;
    _uid = null;
    _token = null;
    await _refreshSub?.cancel();
    _refreshSub = null;
    await _foregroundSub?.cancel();
    _foregroundSub = null;
    if (uid == null || token == null) return;
    try {
      await _tokens.deleteToken(uid: uid, token: token);
      await _messaging.deleteToken();
    } catch (_) {}
  }

  Future<void> _store(String uid, String token) async {
    await _tokens.saveToken(uid: uid, token: token);
    _token = token;
  }

  Future<void> _attachTapHandlers() async {
    if (_tapHandlersAttached) return;
    _tapHandlersAttached = true;
    _openedSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _handleTap(initial);
  }

  void _handleTap(RemoteMessage message) {
    _notifications.openFromNotification(message.data['threadId'] as String?);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    final uid = _uid;
    final Object? rawThreadId = message.data['threadId'];
    final Object? rawMessageId = message.data['messageId'];
    if (uid == null ||
        rawThreadId is! String ||
        rawThreadId.isEmpty ||
        rawMessageId is! String ||
        rawMessageId.isEmpty) {
      return;
    }
    if (message.data['eventType'] == 'ringRequest') {
      final source = message.data['ringSource'] == 'custom'
          ? 'custom'
          : 'system';
      final oldMode = _ringString(message.data['ringMode'], 'ringAndVibrate');
      final oldToggles = _legacyRingToggles(oldMode);
      final ringSoundEnabled = _ringBool(
        message.data['ringSoundEnabled'],
        oldToggles.ring,
      );
      final vibrationEnabled = _ringBool(
        message.data['vibrationEnabled'],
        oldToggles.vibrate,
      );
      final flashlightEnabled = message.data['ringFlashlightEnabled'] == 'true';
      if (message.data['ringEnabled'] == 'true' &&
          (source == 'system' ||
              ringSoundEnabled ||
              vibrationEnabled ||
              flashlightEnabled)) {
        unawaited(() async {
          try {
            await AndroidRingAlerts.startAlert(
              alertId: rawMessageId,
              source: source,
              ringSoundEnabled: ringSoundEnabled,
              vibrationEnabled: vibrationEnabled,
              timeoutSeconds:
                  int.tryParse(message.data['ringTimeoutSeconds'] ?? '') ?? 5,
              title: _ringString(
                message.data['ringTitle'],
                RingAlertPreferences.defaultNotificationTitle,
              ),
              body: _ringString(
                message.data['ringBody'],
                RingAlertPreferences.defaultNotificationBody,
              ),
              ringtoneUri: _ringtoneUri(message.data['ringtoneUri']),
              vibrationPattern: _ringString(
                message.data['ringVibrationPattern'],
                'standard',
              ),
              flashlightEnabled: flashlightEnabled,
              flashPattern: _ringString(
                message.data['ringFlashPattern'],
                'slowBlink',
              ),
              allowFlashInBackground: true,
            );
          } catch (error) {
            debugPrint('Could not start ring request alert: $error');
          }
          try {
            await _notifications.showRingRequestNotification(
              threadId: rawThreadId,
              alertId: rawMessageId,
              title: _ringString(
                message.data['ringTitle'],
                RingAlertPreferences.defaultNotificationTitle,
              ),
              body: _ringString(
                message.data['ringBody'],
                RingAlertPreferences.defaultNotificationBody,
              ),
              preferences: IncomingChatAlertPreferences(
                source: source == 'custom'
                    ? NotificationAlertSource.custom
                    : NotificationAlertSource.system,
                vibrationEnabled: vibrationEnabled,
              ),
            );
          } catch (error) {
            debugPrint('Could not show ring request notification: $error');
          }
        }());
      }
    }
    unawaited(
      scheduleChatReceive(
        uid: uid,
        threadId: rawThreadId,
        messageId: rawMessageId,
      ).catchError((Object error, StackTrace stack) {
        debugPrint('Chat background receive could not be scheduled.');
      }),
    );
  }

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    await _openedSub?.cancel();
    await _foregroundSub?.cancel();
  }
}
