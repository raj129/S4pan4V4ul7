import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/location/app_location.dart';
import '../../../../core/location/location_source.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import '../../../vault/data/repositories/storage_string_kv.dart';

import '../../domain/entities/live_location.dart';
import '../../domain/repositories/live_location_repository.dart';
import 'device_battery.dart';

typedef LiveLocationUpdates = FutureOr<Stream<LiveLocationPoint>> Function();

/// Tells the partner the sharer's battery is low. Sent once per session.
typedef LowBatteryNotifier =
    Future<void> Function({
      required String threadId,
      required String senderId,
      required String recipientUid,
      required int level,
    });

/// Owns a single active Android live-location session and its GPS subscription.
class LiveLocationService with WidgetsBindingObserver {
  LiveLocationService({
    required LiveLocationRepository repository,
    LiveLocationUpdates? locationUpdates,
    SettingsRepository? settingsRepository,
    DateTime Function()? clock,
    BatteryReader? battery,
    LowBatteryNotifier? onLowBattery,
    StorageStringKv? store,
    Duration batteryReadTimeout = const Duration(seconds: 5),
  }) : _repository = repository,
       _locationUpdates =
           locationUpdates ?? (() => _geolocatorUpdates(settingsRepository)),
       _clock = clock ?? DateTime.now,
       _battery = battery,
       _onLowBattery = onLowBattery,
       _store = store,
       _batteryReadTimeout = batteryReadTimeout {
    WidgetsBinding.instance.addObserver(this);
  }

  final LiveLocationRepository _repository;
  final LiveLocationUpdates _locationUpdates;
  final DateTime Function() _clock;
  final BatteryReader? _battery;
  final LowBatteryNotifier? _onLowBattery;
  final StorageStringKv? _store;
  final Duration _batteryReadTimeout;
  final _uuid = const Uuid();

  Timer? _sessionExpiryTimer;
  Timer? _locationRetryTimer;
  StreamSubscription<LiveLocationPoint>? _positionSubscription;
  StreamSubscription<LiveLocationRefreshRequest?>? _refreshRequestSubscription;
  int _locationRetryAttempt = 0;
  int _locationStreamGeneration = 0;
  LiveLocationPoint? _lastPublishedPoint;
  DateTime? _lastPublishedAt;
  DateTime? _activeStartedAt;
  String? _activeThreadId;
  String? _activeUserId;
  String? _activeRecipientUid;
  String? _activeSessionId;
  DateTime? _activeExpiresAt;
  bool _lowBatteryNotified = false;
  bool _writeInFlight = false;
  bool _disposed = false;
  String? _lastHandledRefreshRequestToken;

  final _activeSessionController =
      StreamController<LiveLocationSession?>.broadcast();
  final _errorController = StreamController<Object>.broadcast();

  Stream<LiveLocationSession?> get activeSessionStream =>
      _activeSessionController.stream;
  Stream<Object> get errors => _errorController.stream;

  bool get isSharing => _activeThreadId != null;
  String? get activeThreadId => _activeThreadId;
  String? get activeSessionId => _activeSessionId;
  DateTime? get activeExpiresAt => _activeExpiresAt;

  static const double minDisplacementMeters = 15;
  static const Duration minWriteInterval = Duration(seconds: 10);
  static const Duration maxHeartbeatInterval = Duration(seconds: 45);
  static const Duration maxSessionDuration = Duration(hours: 8);
  static const Duration writeTimeout = Duration(seconds: 20);
  static const storageKey = 'chat.live_location_session.v1';

  /// Battery percentage at or below which the partner is told (when not charging).
  static const int lowBatteryThreshold = 15;

  Future<String> startSharing({
    required String threadId,
    required String userId,
    required Duration duration,
    required LiveLocationPoint initialPoint,
    String? recipientUid,
  }) async {
    if (_disposed) throw StateError('LiveLocationService is disposed.');
    if (duration <= Duration.zero || duration > maxSessionDuration) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Must be between 0 and 8 hours.',
      );
    }
    if (isSharing) await stopSharing();

    final now = _clock().toUtc();
    final expiresAt = now.add(duration);
    final sessionId = _uuid.v4();
    _lowBatteryNotified = false;
    final firstPoint = await _withBattery(
      initialPoint,
      threadId: threadId,
      userId: userId,
      recipientUid: recipientUid,
    );
    final startWrite = _repository.startSession(
      sessionId: sessionId,
      threadId: threadId,
      userId: userId,
      duration: duration,
      initialPoint: firstPoint,
    );
    try {
      await startWrite.timeout(writeTimeout);
    } on TimeoutException {
      unawaited(
        startWrite
            .then<void>((_) {
              return _repository.stopSession(
                sessionId: sessionId,
                threadId: threadId,
                userId: userId,
              );
            })
            .catchError((Object error) {
              _reportError(error);
            }),
      );
      rethrow;
    }

    _activeThreadId = threadId;
    _activeUserId = userId;
    _activeRecipientUid = recipientUid;
    _activeSessionId = sessionId;
    _activeStartedAt = now;
    _activeExpiresAt = expiresAt;
    _lastHandledRefreshRequestToken = null;
    _lastPublishedPoint = firstPoint;
    _lastPublishedAt = now;
    await _persistActive();
    _emitActiveSession(firstPoint);

    _sessionExpiryTimer = Timer(duration, () {
      unawaited(_stopAfterExpiry());
    });
    await _subscribeToLocationUpdates();
    _watchRefreshRequests();
    return sessionId;
  }

  /// Re-attaches to a session that was sharing before the app process was
  /// stopped by Android, as long as it has not expired and was not stopped.
  ///
  /// Does nothing when a session is already active on this device.
  Future<void> restore() async {
    if (_disposed || isSharing) return;
    final store = _store;
    if (store == null) return;
    try {
      final saved = await _readPersisted(store);
      if (saved == null || _disposed || isSharing) return;

      final now = _clock().toUtc();
      if (!now.isBefore(saved.expiresAt)) {
        await _forgetPersisted();
        return;
      }

      _activeThreadId = saved.threadId;
      _activeUserId = saved.userId;
      _activeRecipientUid = saved.recipientUid;
      _activeSessionId = saved.sessionId;
      _activeStartedAt = saved.startedAt;
      _activeExpiresAt = saved.expiresAt;
      _lastHandledRefreshRequestToken = null;
      _lastPublishedPoint = null;
      _lastPublishedAt = null;
      _lowBatteryNotified = false;
      _locationRetryAttempt = 0;

      _sessionExpiryTimer = Timer(saved.expiresAt.difference(now), () {
        unawaited(_stopAfterExpiry());
      });
      await _subscribeToLocationUpdates();
      _watchRefreshRequests();
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _persistActive() async {
    final store = _store;
    final threadId = _activeThreadId;
    final userId = _activeUserId;
    final sessionId = _activeSessionId;
    final startedAt = _activeStartedAt;
    final expiresAt = _activeExpiresAt;
    if (store == null ||
        threadId == null ||
        userId == null ||
        sessionId == null ||
        startedAt == null ||
        expiresAt == null) {
      return;
    }
    try {
      await store.write(
        storageKey,
        jsonEncode({
          'sessionId': sessionId,
          'threadId': threadId,
          'userId': userId,
          'recipientUid': _activeRecipientUid,
          'startedAt': startedAt.millisecondsSinceEpoch,
          'expiresAt': expiresAt.millisecondsSinceEpoch,
        }),
      );
    } catch (error) {
      _reportError(error);
    }
  }

  Future<_PersistedSession?> _readPersisted(StorageStringKv store) async {
    final raw = await store.read(storageKey);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return _PersistedSession(
        sessionId: json['sessionId'] as String,
        threadId: json['threadId'] as String,
        userId: json['userId'] as String,
        recipientUid: json['recipientUid'] as String?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(
          json['startedAt'] as int,
          isUtc: true,
        ),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          json['expiresAt'] as int,
          isUtc: true,
        ),
      );
    } catch (_) {
      await _forgetPersisted();
      return null;
    }
  }

  Future<void> _forgetPersisted() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.delete(storageKey);
    } catch (error) {
      _reportError(error);
    }
  }

  void _watchRefreshRequests() {
    final threadId = _activeThreadId;
    final sessionId = _activeSessionId;
    if (threadId == null || sessionId == null) return;
    try {
      _refreshRequestSubscription = _repository
          .watchRefreshRequest(sessionId: sessionId, threadId: threadId)
          .listen(
            (request) {
              if (request == null ||
                  !request.isPending ||
                  request.requestedBy == _activeUserId ||
                  request.requestToken == _lastHandledRefreshRequestToken) {
                return;
              }
              _lastHandledRefreshRequestToken = request.requestToken;
              unawaited(_handleRefreshRequest(request.requestToken));
            },
            onError: (Object error, StackTrace stackTrace) {
              _reportError(error);
            },
          );
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _handleRefreshRequest(String requestToken) async {
    final threadId = _activeThreadId;
    final sessionId = _activeSessionId;
    if (threadId == null || sessionId == null || !isSharing) return;
    try {
      await refreshSharing();
      await _repository.acknowledgeRefreshRequest(
        sessionId: sessionId,
        threadId: threadId,
        requestToken: requestToken,
      );
    } catch (error) {
      if (_lastHandledRefreshRequestToken == requestToken) {
        _lastHandledRefreshRequestToken = null;
      }
      _reportError(error);
    }
  }

  /// Restart location collection for the currently active session.
  ///
  /// This cannot resume a session after it has been stopped or expired.
  Future<void> refreshSharing() async {
    if (_disposed) throw StateError('LiveLocationService is disposed.');
    final expiresAt = _activeExpiresAt;
    if (!isSharing ||
        expiresAt == null ||
        !_clock().toUtc().isBefore(expiresAt)) {
      throw StateError('There is no active live-location session to refresh.');
    }
    _locationRetryAttempt = 0;
    await _restartLocationUpdates();
  }

  Future<void> _subscribeToLocationUpdates() async {
    if (_disposed || !isSharing || _positionSubscription != null) return;
    final generation = ++_locationStreamGeneration;
    try {
      final updates = await _locationUpdates();
      if (generation != _locationStreamGeneration || !isSharing) return;
      _positionSubscription = updates.listen(
        (point) {
          if (generation != _locationStreamGeneration || !isSharing) return;
          _locationRetryTimer?.cancel();
          _locationRetryTimer = null;
          _locationRetryAttempt = 0;
          unawaited(_handleLocation(point));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (generation != _locationStreamGeneration) return;
          _positionSubscription = null;
          _reportError(error);
          _scheduleLocationRetry();
        },
        onDone: () {
          if (generation != _locationStreamGeneration) return;
          _positionSubscription = null;
          _scheduleLocationRetry();
        },
        cancelOnError: true,
      );
    } catch (error) {
      _reportError(error);
      _scheduleLocationRetry();
    }
  }

  void _scheduleLocationRetry() {
    final expiresAt = _activeExpiresAt;
    if (_disposed ||
        !isSharing ||
        expiresAt == null ||
        _locationRetryTimer != null) {
      return;
    }
    if (!_clock().toUtc().isBefore(expiresAt)) {
      unawaited(_stopAfterExpiry());
      return;
    }
    _locationRetryAttempt++;
    final seconds = _locationRetryAttempt >= 6
        ? 30
        : 1 << (_locationRetryAttempt - 1);
    _locationRetryTimer = Timer(Duration(seconds: seconds), () {
      _locationRetryTimer = null;
      unawaited(_restartLocationUpdates());
    });
  }

  Future<void> _restartLocationUpdates() async {
    final expiresAt = _activeExpiresAt;
    if (_disposed || !isSharing || expiresAt == null) return;
    if (!_clock().toUtc().isBefore(expiresAt)) {
      await _stopAfterExpiry();
      return;
    }
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    final previous = _positionSubscription;
    _positionSubscription = null;
    final restartGeneration = ++_locationStreamGeneration;
    try {
      await previous?.cancel();
    } catch (error) {
      _reportError(error);
      _scheduleLocationRetry();
      return;
    }
    final latestExpiry = _activeExpiresAt;
    if (_disposed ||
        !isSharing ||
        restartGeneration != _locationStreamGeneration) {
      return;
    }
    if (latestExpiry == null || !_clock().toUtc().isBefore(latestExpiry)) {
      await _stopAfterExpiry();
      return;
    }
    await _subscribeToLocationUpdates();
  }

  Future<void> _handleLocation(LiveLocationPoint point) async {
    try {
      await onNewLocation(point);
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> onNewLocation(LiveLocationPoint point) async {
    if (!isSharing || _writeInFlight) return;

    final now = _clock().toUtc();
    final expiresAt = _activeExpiresAt;
    if (expiresAt == null || !now.isBefore(expiresAt)) {
      await stopSharing();
      return;
    }

    final previousPoint = _lastPublishedPoint;
    final previousTime = _lastPublishedAt;
    if (previousPoint == null || previousTime == null) {
      await _publish(point);
      return;
    }

    final elapsed = now.difference(previousTime);
    if (elapsed < minWriteInterval) return;

    final moved = _calculateDistance(
      previousPoint.latitude,
      previousPoint.longitude,
      point.latitude,
      point.longitude,
    );
    if (moved >= minDisplacementMeters || elapsed >= maxHeartbeatInterval) {
      await _publish(point);
    }
  }

  Future<void> _publish(LiveLocationPoint point) async {
    final threadId = _activeThreadId;
    final userId = _activeUserId;
    final sessionId = _activeSessionId;
    if (threadId == null ||
        userId == null ||
        sessionId == null ||
        _writeInFlight) {
      return;
    }

    _writeInFlight = true;
    try {
      final enriched = await _withBattery(
        point,
        threadId: threadId,
        userId: userId,
        recipientUid: _activeRecipientUid,
      );
      await _repository
          .updateLocation(
            sessionId: sessionId,
            threadId: threadId,
            userId: userId,
            point: enriched,
          )
          .timeout(writeTimeout);
      _lastPublishedPoint = enriched;
      _lastPublishedAt = _clock().toUtc();
      _emitActiveSession(enriched);
    } catch (error) {
      _reportError(error);
    } finally {
      _writeInFlight = false;
    }
  }

  /// Adds the battery level to [point] and sends the one-time low-battery
  /// notice when it first drops to the threshold while not charging.
  Future<LiveLocationPoint> _withBattery(
    LiveLocationPoint point, {
    required String threadId,
    required String userId,
    required String? recipientUid,
  }) async {
    final reader = _battery;
    if (reader == null) return point;
    final status = await reader.read().timeout(
      _batteryReadTimeout,
      onTimeout: () => null,
    );
    if (status == null) return point;

    final low = !status.charging && status.level <= lowBatteryThreshold;
    final notify = _onLowBattery;
    if (!low) {
      _lowBatteryNotified = false;
    } else if (!_lowBatteryNotified && notify != null && recipientUid != null) {
      _lowBatteryNotified = true;
      // Not awaited: a slow or offline chat write must not hold up location.
      unawaited(
        notify(
          threadId: threadId,
          senderId: userId,
          recipientUid: recipientUid,
          level: status.level,
        ).catchError((Object error) {
          _lowBatteryNotified = false;
          _reportError(error);
        }),
      );
    }
    return point.withBattery(level: status.level, charging: status.charging);
  }

  Future<void> stopSharing() async {
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    _locationStreamGeneration++;
    await _forgetPersisted();
    final refreshSubscription = _refreshRequestSubscription;
    _refreshRequestSubscription = null;
    await refreshSubscription?.cancel();
    final subscription = _positionSubscription;
    _positionSubscription = null;
    await subscription?.cancel();

    final threadId = _activeThreadId;
    final userId = _activeUserId;
    final sessionId = _activeSessionId;
    if (threadId != null && userId != null && sessionId != null) {
      await _repository
          .stopSession(sessionId: sessionId, threadId: threadId, userId: userId)
          .timeout(writeTimeout);
    }
    _clearActiveSession();
  }

  Future<void> _stopAfterExpiry() async {
    try {
      await stopSharing();
    } catch (error) {
      _reportError(error);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _disposed) return;
    if (!isSharing) {
      unawaited(restore());
      return;
    }
    unawaited(_recoverLocationUpdates());
  }

  Future<void> _recoverLocationUpdates() async {
    final expiresAt = _activeExpiresAt;
    if (expiresAt == null || !_clock().toUtc().isBefore(expiresAt)) {
      await _stopAfterExpiry();
      return;
    }
    _locationRetryAttempt = 0;
    await _restartLocationUpdates();
  }

  void _reportError(Object error) {
    if (!_disposed && !_errorController.isClosed) _errorController.add(error);
  }

  void _clearActiveSession() {
    _activeThreadId = null;
    _activeUserId = null;
    _activeRecipientUid = null;
    _activeSessionId = null;
    _activeStartedAt = null;
    _activeExpiresAt = null;
    _lastPublishedPoint = null;
    _lastPublishedAt = null;
    _activeSessionController.add(null);
  }

  void _emitActiveSession(LiveLocationPoint point) {
    final threadId = _activeThreadId;
    final userId = _activeUserId;
    final sessionId = _activeSessionId;
    final startedAt = _activeStartedAt;
    final expiresAt = _activeExpiresAt;
    if (threadId == null ||
        userId == null ||
        sessionId == null ||
        startedAt == null ||
        expiresAt == null) {
      return;
    }

    _activeSessionController.add(
      LiveLocationSession(
        sessionId: sessionId,
        threadId: threadId,
        userId: userId,
        isActive: true,
        startedAt: startedAt,
        expiresAt: expiresAt,
        lastUpdatedAt: _lastPublishedAt ?? _clock().toUtc(),
        currentPoint: point,
      ),
    );
  }

  static Future<Stream<LiveLocationPoint>> _geolocatorUpdates(
    SettingsRepository? settingsRepository,
  ) async {
    var notificationTitle =
        SettingsRepository.defaultBackgroundLocationAlertTitle;
    var notificationText =
        SettingsRepository.defaultBackgroundLocationAlertText;
    if (settingsRepository != null) {
      try {
        notificationTitle = await settingsRepository
            .getBackgroundLocationAlertTitle();
        notificationText = await settingsRepository
            .getBackgroundLocationAlertText();
      } catch (error) {
        debugPrint(
          'Could not read background-location notification settings: $error',
        );
      }
    }
    return AppLocation.instance
        .updates(
          LocationUpdateConfig(
            // Let the service receive stationary fixes so its heartbeat can
            // keep the remote session fresh; movement filtering happens below.
            distanceFilterMeters: 0,
            interval: minWriteInterval,
            backgroundNotification: true,
            notificationTitle: notificationTitle,
            notificationText: notificationText,
          ),
        )
        .map(
          (fix) => LiveLocationPoint(
            latitude: fix.latitude,
            longitude: fix.longitude,
            accuracy: fix.accuracy,
            heading: fix.heading,
            speed: fix.speed,
            timestamp: fix.timestamp.toUtc(),
          ),
        );
  }

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _degToRad(double degrees) => degrees * (pi / 180);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    _locationStreamGeneration++;
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    unawaited(_refreshRequestSubscription?.cancel());
    _refreshRequestSubscription = null;
    _activeSessionController.close();
    _errorController.close();
  }
}

class _PersistedSession {
  const _PersistedSession({
    required this.sessionId,
    required this.threadId,
    required this.userId,
    required this.recipientUid,
    required this.startedAt,
    required this.expiresAt,
  });

  final String sessionId;
  final String threadId;
  final String userId;
  final String? recipientUid;
  final DateTime startedAt;
  final DateTime expiresAt;
}
