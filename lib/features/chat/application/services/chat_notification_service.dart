import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/entities/chat_thread.dart';
import '../../domain/repositories/thread_repository.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';

typedef ChatNotificationPresenter =
    Future<void> Function({
      required String threadId,
      required String title,
      required String body,
    });

@immutable
class ForegroundChatNotification {
  const ForegroundChatNotification({
    required this.threadId,
    required this.title,
    required this.body,
  });

  final String threadId;
  final String title;
  final String body;
}

/// Emits an in-app alert while the app is visible and a local notification
/// while it is backgrounded, and remembers the tapped conversation.
///
/// The background FCM handler also posts through the local-notification plugin.
/// Both local notifications use the Android tag = threadId and id = 0, so they
/// replace rather than stack duplicates.
/// Foreground unread updates are coalesced to one alert per thread per window.
class ChatNotificationService {
  ChatNotificationService({
    required ThreadRepository threadRepository,
    SettingsRepository? settingsRepository,
    ChatNotificationPresenter? presentNotification,
    bool Function()? isAppForeground,
    DateTime Function()? clock,
  }) : _threadRepository = threadRepository,
       _settingsRepository = settingsRepository,
       _presentNotification = presentNotification,
       _isAppForeground = isAppForeground,
       _clock = clock ?? DateTime.now;

  final ThreadRepository _threadRepository;
  final SettingsRepository? _settingsRepository;
  final ChatNotificationPresenter? _presentNotification;
  final bool Function()? _isAppForeground;
  final DateTime Function() _clock;
  final _plugin = FlutterLocalNotificationsPlugin();

  /// New-message events for the app shell to display as in-app banners.
  final ValueNotifier<ForegroundChatNotification?> foregroundNotification =
      ValueNotifier(null);

  /// Must match `android.notification.channelId` in the Cloud Function and the
  /// default channel declared in AndroidManifest.xml.
  static const channelId = 'chat_messages';

  /// FCM posts tagged notifications with id 0; reusing it lets them replace.
  static const _notificationId = 0;
  static const _testNotificationId = 1;

  /// Keep foreground burst behavior aligned with the Cloud Function throttle.
  static const _alertCooldown = Duration(seconds: 30);

  /// Conversation the user asked to open from a notification. Consumed by the
  /// chat list once the vault and chat are unlocked, so a tap never bypasses
  /// the PIN.
  final ValueNotifier<String?> pendingThreadId = ValueNotifier<String?>(null);

  StreamSubscription<List<ChatThread>>? _sub;
  final _lastUnread = <String, int>{};
  final _lastAlertAt = <String, DateTime>{};
  String? _activeThreadId;
  bool _chatSectionVisible = true;
  bool _initialised = false;
  String? _watchingUid;
  bool _primed = false;

  Future<void> init() async {
    if (_initialised) return;
    if (_presentNotification == null) {
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
    }
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

      if (_chatSectionVisible && thread.threadId == _activeThreadId) {
        _lastUnread[thread.threadId] = 0;
        continue;
      }

      _lastUnread[thread.threadId] = unread;
      if (!_primed || previous == null) continue;
      if (unread <= previous) continue;
      final now = _clock();
      final lastAlert = _lastAlertAt[thread.threadId];
      if (lastAlert != null && now.difference(lastAlert) < _alertCooldown) {
        continue;
      }
      _lastAlertAt[thread.threadId] = now;
      await _notify(thread);
    }
    _primed = true;
  }

  Future<void> _notify(ChatThread thread) async {
    final title = await _incomingChatAlertTitle();
    final body = await _incomingChatAlertText();

    if (_isForeground) {
      foregroundNotification.value = ForegroundChatNotification(
        threadId: thread.threadId,
        title: title,
        body: body,
      );
      return;
    }

    final presentNotification = _presentNotification;
    if (presentNotification != null) {
      await presentNotification(
        threadId: thread.threadId,
        title: title,
        body: body,
      );
      return;
    }
    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: _notificationDetails(tag: thread.threadId),
      payload: thread.threadId,
    );
  }

  Future<void> showTestNotification() async {
    await init();
    final title = await _incomingChatAlertTitle();
    final body = await _incomingChatAlertText();
    final presentNotification = _presentNotification;
    if (presentNotification != null) {
      await presentNotification(
        threadId: 'test-notification',
        title: title,
        body: body,
      );
      return;
    }
    await _plugin.show(
      id: _testNotificationId,
      title: title,
      body: body,
      notificationDetails: _notificationDetails(),
    );
  }

  Future<String> _incomingChatAlertTitle() async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      return SettingsRepository.defaultIncomingChatAlertTitle;
    }
    try {
      return (await settingsRepository.getIncomingChatAlertTitle()).trim();
    } catch (error) {
      debugPrint('Could not read custom notification alert title: $error');
      return SettingsRepository.defaultIncomingChatAlertTitle;
    }
  }

  Future<String> _incomingChatAlertText() async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      return SettingsRepository.defaultIncomingChatAlertText;
    }
    try {
      return (await settingsRepository.getIncomingChatAlertText()).trim();
    } catch (error) {
      debugPrint('Could not read custom notification alert text: $error');
      return SettingsRepository.defaultIncomingChatAlertText;
    }
  }

  NotificationDetails _notificationDetails({String? tag}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          'Chat messages',
          channelDescription: 'Notifies you about new chat messages.',
          importance: Importance.high,
          priority: Priority.high,
          tag: tag,
        ),
      );

  Future<void> setActiveThread(String? threadId) async {
    _activeThreadId = threadId;
    if (threadId != null) {
      _lastUnread[threadId] = 0;
      if (_initialised && _presentNotification == null) {
        try {
          await _plugin.cancel(id: _notificationId, tag: threadId);
        } catch (_) {}
      }
    }
  }

  bool get _isForeground =>
      _isAppForeground?.call() ??
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  /// Whether the chat branch is currently visible in the app.
  void setChatSectionVisible(bool visible) {
    _chatSectionVisible = visible;
  }

  /// Whether [threadId] is open on screen right now.
  bool isActiveThread(String? threadId) =>
      _chatSectionVisible && threadId != null && threadId == _activeThreadId;

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _watchingUid = null;
    _lastUnread.clear();
    _lastAlertAt.clear();
    _primed = false;
  }

  Future<void> dispose() async {
    await stop();
    pendingThreadId.dispose();
    foregroundNotification.dispose();
  }
}
