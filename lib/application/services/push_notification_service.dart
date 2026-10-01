import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/repositories_impl/firestore_message_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../firebase_options.dart';
import '../../domain/repositories/push_token_repository.dart';
import 'chat_notification_service.dart';

@pragma('vm:entry-point')
Future<void> handleChatPushInBackground(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final Object? rawThreadId = message.data['threadId'];
  final Object? rawMessageId = message.data['messageId'];
  if (rawThreadId is! String || rawThreadId.isEmpty) return;
  final threadId = rawThreadId;
  final messageId = rawMessageId is String ? rawMessageId : null;

  if (message.data['notify'] != 'false') {
    final notifications = FlutterLocalNotificationsPlugin();
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await notifications.show(
      id: 0,
      title: 'Calculator',
      body: 'You have a new alert',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          ChatNotificationService.channelId,
          'Chat messages',
          channelDescription: 'Notifies you about new chat messages.',
          importance: Importance.high,
          priority: Priority.high,
          tag: threadId,
        ),
      ),
      payload: threadId,
    );
  }

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null || messageId == null || messageId.isEmpty) return;
  await FirestoreMessageRepository(
    firestore: FirebaseFirestore.instanceFor(
      app: Firebase.app(),
      databaseId: 'default1',
    ),
  ).markDelivered(threadId: threadId, messageIds: [messageId], uid: uid);
}

/// Registers this device for FCM pushes sent by the `onChatMessageCreated`
/// Cloud Function, and routes notification taps to the right conversation.
///
/// Pushes are data-only so the background handler can acknowledge delivery.
/// It displays the same generic local notification that the OS previously
/// displayed for the notification payload.
class PushNotificationService {
  PushNotificationService({
    required PushTokenRepository tokenRepository,
    required ChatNotificationService notificationService,
    required MessageRepository messageRepository,
    FirebaseMessaging? messaging,
  }) : _tokens = tokenRepository,
       _notifications = notificationService,
       _messages = messageRepository,
       _messagingOverride = messaging;

  final PushTokenRepository _tokens;
  final ChatNotificationService _notifications;
  final MessageRepository _messages;
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
    unawaited(
      _messages
          .markDelivered(
            threadId: rawThreadId,
            messageIds: [rawMessageId],
            uid: uid,
          )
          .catchError((_) {}),
    );
  }

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    await _openedSub?.cancel();
    await _foregroundSub?.cancel();
  }
}
