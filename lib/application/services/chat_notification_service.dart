import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/entities/chat_thread.dart';
import '../../domain/repositories/thread_repository.dart';

/// Shows a local notification when an unread count goes up.
class ChatNotificationService {
  ChatNotificationService({required ThreadRepository threadRepository})
    : _threadRepository = threadRepository;

  final ThreadRepository _threadRepository;
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'chat_messages';

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
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    _initialised = true;
  }

  Future<void> start(String myUid) async {
    if (_watchingUid == myUid && _sub != null) return;
    await init();
    await _sub?.cancel();
    _watchingUid = myUid;
    _primed = false;
    _lastUnread.clear();
    _sub = _threadRepository.watchThreadsForUser(myUid).listen(
      (threads) => _onThreads(threads, myUid),
      onError: (_) {},
    );
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
      id: thread.threadId.hashCode,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Chat messages',
          channelDescription: 'Notifies you about new chat messages.',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: thread.threadId,
    );
  }

  Future<void> setActiveThread(String? threadId) async {
    _activeThreadId = threadId;
    if (threadId != null) {
      _lastUnread[threadId] = 0;
      await _plugin.cancel(id: threadId.hashCode);
    }
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _watchingUid = null;
    _lastUnread.clear();
    _primed = false;
  }

  Future<void> dispose() => stop();
}
