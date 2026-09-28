import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

import '../../domain/repositories/push_token_repository.dart';
import 'chat_notification_service.dart';

/// Registers this device for FCM pushes sent by the `onChatMessageCreated`
/// Cloud Function, and routes notification taps to the right conversation.
///
/// Pushes are *notification* messages, so Android displays them itself while
/// the app is in the background or killed — no background isolate is needed.
/// In the foreground Android does not display them; [ChatNotificationService]
/// already covers that case from the live Firestore listener.
class PushNotificationService {
  PushNotificationService({
    required PushTokenRepository tokenRepository,
    required ChatNotificationService notificationService,
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
  bool _tapHandlersAttached = false;

  /// Register the device for [uid]. Safe to call repeatedly.
  Future<void> start(String uid) async {
    if (_uid == uid && _token != null) return;
    _uid = uid;
    try {
      await _attachTapHandlers();
      await _messaging.requestPermission();
      final token = await _messaging.getToken();
      if (token != null) await _store(uid, token);
      await _refreshSub?.cancel();
      _refreshSub = _messaging.onTokenRefresh.listen((fresh) {
        final current = _uid;
        if (current == null) return;
        final stale = _token;
        unawaited(() async {
          if (stale != null && stale != fresh) {
            await _tokens.deleteToken(uid: current, token: stale);
          }
          await _store(current, fresh);
        }().catchError((_) {}));
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

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    await _openedSub?.cancel();
  }
}
