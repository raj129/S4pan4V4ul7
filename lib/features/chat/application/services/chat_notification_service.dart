import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/entities/chat_thread.dart';
import '../../domain/repositories/thread_repository.dart';

/// Shows a local notification when an unread count goes up, and remembers
/// which conversation a tapped notification belongs to.
///
/// This covers the app while its process is alive. The background FCM handler
/// also posts through the local-notification plugin. Both use the Android tag
/// = threadId and id = 0, so they replace rather than stack duplicates.
class ChatNotificationService {
  ChatNotificationService({required ThreadRepository threadRepository})
    : _threadRepository = threadRepository;

  final ThreadRepository _threadRepository;
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Must match `android.notification.channelId` in the Cloud Function and the
  /// default channel declared in AndroidManifest.xml.
  static const channelId = 'chat_messages';

  /// FCM posts tagged notifications with id 0; reusing it lets them replace.
  static const _notificationId = 0;

  /// Conversation the user asked to open from a notification. Consumed by the
  /// chat list once the vault and chat are unlocked, so a tap never bypasses
  /// the PIN.
  final ValueNotifier<String?> pendingThreadId = ValueNotifier<String?>(null);

  StreamSubscription<List<ChatThread>>? _sub;
  final _lastUnread = <String, int>{};
  String? _activeThreadId;
  bool _initialised = false;
  String? _watchingUid;
  bool _primed = false;

  Future<void> init() async {
    if (_initialised) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) =>
          openFromNotification(response.payload),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        'Chat messages',
        description: 'Notifies you about new chat messages.',
        importance: Importance.high,
      ),
    );
    await android?.requestNotificationsPermission();
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        openFromNotification(launch!.notificationResponse?.payload);
      }
    } catch (_) {}
    _initialised = true;
  }

  /// Record a tapped notification's thread for the chat list to open.
  void openFromNotification(String? threadId) {
    if (threadId == null || threadId.isEmpty) return;
    pendingThreadId.value = threadId;
  }

  /// Hand over and clear the pending thread, if any.
  String? takePendingThread() {
    final id = pendingThreadId.value;
    pendingThreadId.value = null;
    return id;
  }

  Future<void> start(String myUid) async {
    if (_watchingUid == myUid && _sub != null) return;
    await init();
    await _sub?.cancel();
    _watchingUid = myUid;
    _primed = false;
    _lastUnread.clear();
    _sub = _threadRepository
        .watchThreadsForUser(myUid)
        .listen((threads) => _onThreads(threads, myUid), onError: (_) {});
  }

  Future<void> _onThreads(List<ChatThread> threads, String myUid) async {
    for (final thread in threads) {
      final unread = thread.unreadCounts[myUid] ?? 0;
      final previous = _lastUnread[thread.threadId];

      if (thread.threadId == _activeThreadId) {
        _lastUnread[thread.threadId] = 0;
        continue;
      }

      _lastUnread[thread.threadId] = unread;
      if (!_primed || previous == null) continue;
      if (unread <= previous) continue;
      await _notify(thread, unread);
    }
    _primed = true;
  }

  Future<void> _notify(ChatThread thread, int unread) async {
    final title = 'Calculator';
    final body = unread == 1
        ? 'You have a new alert'
        : 'You have $unread new alerts';

    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Chat messages',
          channelDescription: 'Notifies you about new chat messages.',
          importance: Importance.high,
          priority: Priority.high,
          tag: thread.threadId,
        ),
      ),
      payload: thread.threadId,
    );
  }

  Future<void> setActiveThread(String? threadId) async {
    _activeThreadId = threadId;
    if (threadId != null) {
      _lastUnread[threadId] = 0;
      if (_initialised) {
        try {
          await _plugin.cancel(id: _notificationId, tag: threadId);
        } catch (_) {}
      }
    }
  }

  /// Whether [threadId] is open on screen right now.
  bool isActiveThread(String? threadId) =>
      threadId != null && threadId == _activeThreadId;

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _watchingUid = null;
    _lastUnread.clear();
    _primed = false;
  }

  Future<void> dispose() async {
    await stop();
    pendingThreadId.dispose();
  }
}
