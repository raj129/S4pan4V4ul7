import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/entities/chat_thread.dart';
import '../../domain/repositories/thread_repository.dart';
import '../../domain/repositories/user_repository.dart';

/// Shows a local notification when an unread count goes up.
///
/// There is no push server: Cloud Functions require the Blaze plan and the FCM
/// HTTP v1 API needs a service-account token that must never ship inside an
/// APK. Instead this rides the Firestore thread listener the app already keeps
/// open, so notifications arrive whenever the process is alive.
///
/// The trade-off is that a killed process receives nothing until it is
/// reopened; at this scale that is an acceptable exchange for not running a
/// backend.
class ChatNotificationService {
  ChatNotificationService({
    required ThreadRepository threadRepository,
    required UserRepository userRepository,
  }) : _threadRepository = threadRepository,
       _userRepository = userRepository;

  final ThreadRepository _threadRepository;
  final UserRepository _userRepository;
  final _plugin = FlutterLocalNotificationsPlugin();

  static const _channelId = 'chat_messages';

  StreamSubscription<List<ChatThread>>? _sub;

  /// Last unread count seen per thread, so only *increases* notify.
  final _lastUnread = <String, int>{};

  /// Thread currently on screen; its messages are being read, not missed.
  String? _activeThreadId;

  bool _initialised = false;

  /// Uid currently being watched, so a repeated [start] for the same session is
  /// a no-op instead of resetting the unread baseline.
  String? _watchingUid;

  /// Suppresses the very first snapshot.
  ///
  /// Firestore replays the current state when a listener attaches, which would
  /// otherwise fire a notification for every already-unread thread on launch.
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

  /// Begin watching for new messages addressed to [myUid].
  Future<void> start(String myUid) async {
    if (_watchingUid == myUid && _sub != null) return;
    await init();
    await _sub?.cancel();
    _watchingUid = myUid;
    _primed = false;
    _lastUnread.clear();
    _sub = _threadRepository.watchThreadsForUser(myUid).listen(
      (threads) => _onThreads(threads, myUid),
      onError: (_) {
        // A dropped listener must not take the app down; the thread list shows
        // the same error through its own subscription.
      },
    );
  }

  Future<void> _onThreads(List<ChatThread> threads, String myUid) async {
    for (final thread in threads) {
      final unread = thread.unreadCounts[myUid] ?? 0;
      final previous = _lastUnread[thread.threadId];
      _lastUnread[thread.threadId] = unread;

      if (!_primed || previous == null) continue;
      if (unread <= previous) continue;
      if (thread.threadId == _activeThreadId) continue;

      await _notify(thread, myUid, unread);
    }
    _primed = true;
  }

  Future<void> _notify(ChatThread thread, String myUid, int unread) async {
    final otherUid = thread.otherParticipantId(myUid);
    final sender = await _userRepository.getUserById(otherUid);
    final title = sender?.displayName ?? sender?.email ?? 'New message';

    // The stored preview is ciphertext and the thread key is not available
    // here, so the body reports the count rather than the content. That also
    // keeps message text off the lock screen.
    final body = unread == 1 ? 'New message' : '$unread new messages';

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

  /// Mark a thread as on-screen, and clear any notification already shown.
  Future<void> setActiveThread(String? threadId) async {
    _activeThreadId = threadId;
    if (threadId != null) {
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
