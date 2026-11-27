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
import 'live_location_health.dart';

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
    Duration Function()? elapsed,
  }) : _repository = repository,
       _locationUpdates =
           locationUpdates ?? (() => _geolocatorUpdates(settingsRepository)),
       _clock = clock ?? DateTime.now,
       _battery = battery,
       _onLowBattery = onLowBattery,
       _store = store,
       _batteryReadTimeout = batteryReadTimeout,
       health = LiveLocationHealth(store: store, clock: clock),
       _elapsedOverride = elapsed {
    _uptime.start();
    WidgetsBinding.instance.addObserver(this);
  }

  final LiveLocationRepository _repository;
  final LiveLocationUpdates _locationUpdates;
  final DateTime Function() _clock;
  final BatteryReader? _battery;
  final LowBatteryNotifier? _onLowBattery;
  final StorageStringKv? _store;
  final Duration _batteryReadTimeout;
  final LiveLocationHealth health;
  final Duration Function()? _elapsedOverride;
  final Stopwatch _uptime = Stopwatch();
  Duration get _elapsed => _elapsedOverride?.call() ?? _uptime.elapsed;
  Duration? _lastCallbackAt;
  Duration? _lastFreshFixAt;
  Duration? _subscriptionStartedAt;
  Duration _nextRecoveryAt = Duration.zero;
  Timer? _healthTimer;
  Future<void>? _restartOperation;
  Future<void>? _refreshOperation;
  Completer<void>? _freshPublication;
  DateTime? _refreshRequestedAt;
  LiveLocationRefreshRequest? _pendingRefresh;
  bool _handlingRefresh = false;
  int _sessionGeneration = 0;
  int? _writeOwner;
  Future<void> _stateStorage = Future.value();
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
  static const silenceTimeout = Duration(seconds: 60);
  static const operationTimeout = Duration(seconds: 10);
  static const refreshTimeout = Duration(seconds: 90);

  Map<String, Object?> get healthSnapshot => {
    'sharing': isSharing,
    'callbackAgeMs': _lastCallbackAt == null
        ? null
        : (_elapsed - _lastCallbackAt!).inMilliseconds,
    'lastPublishedAt': _lastPublishedAt?.toUtc().toIso8601String(),
    'freshFixAgeMs': _lastFreshFixAt == null
        ? null
        : (_elapsed - _lastFreshFixAt!).inMilliseconds,
    'retryAttempt': _locationRetryAttempt,
    'restarting': _restartOperation != null,
    'writeInFlight': _writeInFlight,
  };

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
    final generation = ++_sessionGeneration;

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

    if (_disposed || generation != _sessionGeneration) {
      await _repository
          .stopSession(sessionId: sessionId, threadId: threadId, userId: userId)
          .timeout(writeTimeout);
      throw StateError('Live location start was cancelled.');
    }
    _activeThreadId = threadId;
    _activeUserId = userId;
    _activeRecipientUid = recipientUid;
    _activeSessionId = sessionId;
    _activeStartedAt = now;
    _activeExpiresAt = expiresAt;
    _locationRetryAttempt = 0;
    _lastHandledRefreshRequestToken = null;
    _lastPublishedPoint = firstPoint;
    _lastPublishedAt = now;
    await _persistActive();
    if (_disposed || generation != _sessionGeneration) {
      throw StateError('Live location start was cancelled.');
    }
    _emitActiveSession(firstPoint);

    _sessionExpiryTimer = Timer(duration, () {
      unawaited(_stopAfterExpiry());
    });
    health.record('started');
    _startHealthChecks();
    await _recoverSafely('start');
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
    final generation = _sessionGeneration;
    try {
      final saved = await _readPersisted(store);
      if (saved == null ||
          _disposed ||
          isSharing ||
          generation != _sessionGeneration) {
        return;
      }

      final now = _clock().toUtc();
      if (!now.isBefore(saved.expiresAt)) {
        await _forgetPersisted();
        return;
      }

      _activeThreadId = saved.threadId;
      _sessionGeneration++;
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
      health.record('restored');
      _startHealthChecks();
      await _recoverSafely('restore');
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
      final payload = jsonEncode({
        'sessionId': sessionId,
        'threadId': threadId,
        'userId': userId,
        'recipientUid': _activeRecipientUid,
        'startedAt': startedAt.millisecondsSinceEpoch,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
      });
      await _queueStateStorage(() => store.write(storageKey, payload));
    } catch (error) {
      _reportError(error);
    }
  }

  Future<_PersistedSession?> _readPersisted(StorageStringKv store) async {
    await _stateStorage;
    final raw = await store.read(storageKey).timeout(operationTimeout);
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
      await _queueStateStorage(() => store.delete(storageKey));
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _queueStateStorage(Future<void> Function() action) {
    final operation = _stateStorage.then(
      (_) => action().timeout(operationTimeout),
    );
    // Keep subsequent cleanup usable after a failed storage operation.
    _stateStorage = operation.catchError((Object _) {});
    return operation;
  }

  void _watchRefreshRequests() {
    if (_disposed || _refreshRequestSubscription != null) return;
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
              _pendingRefresh = request;
              unawaited(_handleRefreshRequest());
            },
            onError: (Object error, StackTrace stackTrace) {
              _reportError(error);
            },
          );
    } catch (error) {
      _reportError(error);
    }
  }

  Future<void> _handleRefreshRequest() async {
    final request = _pendingRefresh;
    if (request == null || _handlingRefresh || _disposed) return;
    final threadId = _activeThreadId;
    final sessionId = _activeSessionId;
    if (threadId == null || sessionId == null || !isSharing) return;
    final generation = _sessionGeneration;
    _handlingRefresh = true;
    try {
      await refreshSharing();
      if (generation != _sessionGeneration || _disposed) return;
      await _repository
          .acknowledgeRefreshRequest(
            sessionId: sessionId,
            threadId: threadId,
            requestToken: request.requestToken,
          )
          .timeout(writeTimeout);
      if (_pendingRefresh == request) _pendingRefresh = null;
      health.record('refresh_acknowledged');
    } catch (error) {
      if (generation == _sessionGeneration && !_disposed) {
        _nextRecoveryAt = _elapsed + const Duration(seconds: 30);
        _reportError(error);
      }
    } finally {
      if (generation == _sessionGeneration) _handlingRefresh = false;
    }
  }

  /// Apply foreground-notification settings without waiting for a GPS fix.
  Future<void> refreshNotification() => _restartLocationUpdates('notification');

  /// Restart collection and wait for a fresh, successfully published location.
  ///
  /// This cannot resume a session after it has been stopped or expired.
  Future<void> refreshSharing() {
    final existing = _refreshOperation;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _refreshSharing().whenComplete(() {
      if (identical(_refreshOperation, operation)) _refreshOperation = null;
    });
    _refreshOperation = operation;
    return operation;
  }

  Future<void> _refreshSharing() async {
    if (_disposed) throw StateError('LiveLocationService is disposed.');
    final expiresAt = _activeExpiresAt;
    if (!isSharing ||
        expiresAt == null ||
        !_clock().toUtc().isBefore(expiresAt)) {
      throw StateError('There is no active live-location session to refresh.');
    }
    final waiter = Completer<void>();
    _freshPublication = waiter;
    _refreshRequestedAt = _clock().toUtc();
    health.record('refresh_requested');
    // Install the error handler before stop/disposal can cancel the waiter.
    final published = waiter.future.timeout(refreshTimeout);
    unawaited(published.catchError((Object _) {}));
    try {
      await _restartLocationUpdates('refresh');
      await published;
    } finally {
      if (!waiter.isCompleted) {
        waiter.completeError(
          StateError('Refresh did not publish a fresh fix.'),
        );
      }
      if (identical(_freshPublication, waiter)) {
        _freshPublication = null;
        _refreshRequestedAt = null;
      }
    }
  }

  Future<void> _subscribeToLocationUpdates() async {
    if (_disposed || !isSharing || _positionSubscription != null) return;
    final generation = ++_locationStreamGeneration;
    try {
      final updates = await Future<Stream<LiveLocationPoint>>.sync(
        _locationUpdates,
      ).timeout(operationTimeout);
      if (generation != _locationStreamGeneration || !isSharing) return;
      _subscriptionStartedAt = _elapsed;
      _positionSubscription = updates.listen(
        (point) {
          if (generation != _locationStreamGeneration || !isSharing) return;
          final wasRecovering = _locationRetryAttempt > 0;
          _lastCallbackAt = _elapsed;
          if (!_isFreshFix(point)) {
            health.record('old_fix_ignored');
            return;
          }
          _lastFreshFixAt = _elapsed;
          _locationRetryTimer?.cancel();
          _locationRetryTimer = null;
          _locationRetryAttempt = 0;
          _nextRecoveryAt = Duration.zero;
          if (wasRecovering) health.record('source_recovered');
          unawaited(_handleLocation(point));
        },
        onError: (Object error, StackTrace stackTrace) {
          if (generation != _locationStreamGeneration) return;
          // Retain ownership until the coordinator has awaited cancellation.
          _locationStreamGeneration++;
          health.record('source_error', error: error);
          _reportError(error);
          _scheduleLocationRetry();
        },
        onDone: () {
          if (generation != _locationStreamGeneration) return;
          _positionSubscription = null;
          health.record('source_done');
          _scheduleLocationRetry();
        },
        cancelOnError: false,
      );
    } catch (error) {
      if (generation != _locationStreamGeneration || _disposed || !isSharing) {
        rethrow;
      }
      _reportError(error);
      _scheduleLocationRetry();
      rethrow;
    }
  }

  void _startHealthChecks() {
    _lastCallbackAt = null;
    _lastFreshFixAt = null;
    _subscriptionStartedAt = _elapsed;
    _nextRecoveryAt = Duration.zero;
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_disposed || !isSharing) return;
      final expires = _activeExpiresAt;
      if (expires == null || !_clock().toUtc().isBefore(expires)) {
        unawaited(_stopAfterExpiry());
        return;
      }
      if (_elapsed < _nextRecoveryAt) return;
      if (_pendingRefresh != null && !_handlingRefresh) {
        unawaited(_handleRefreshRequest());
      }
      var last = _lastFreshFixAt;
      final started = _subscriptionStartedAt;
      if (last == null || (started != null && started > last)) last = started;
      if (last == null ||
          _elapsed - last < silenceTimeout ||
          _restartOperation != null ||
          _locationRetryTimer != null) {
        return;
      }
      health.record('source_silent');
      unawaited(_recoverSafely('silence'));
    });
  }

  Future<void> _recoverSafely(String reason) async {
    try {
      await _restartLocationUpdates(reason);
    } catch (_) {
      // The coordinator reports and schedules failed recovery.
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
    health.record('retry_scheduled', attempt: _locationRetryAttempt);
    _locationRetryTimer = Timer(Duration(seconds: seconds), () {
      _locationRetryTimer = null;
      unawaited(_recoverSafely('retry'));
    });
  }

  Future<void> _restartLocationUpdates(String reason) {
    final existing = _restartOperation;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _performRestart(reason).whenComplete(() {
      if (identical(_restartOperation, operation)) _restartOperation = null;
    });
    _restartOperation = operation;
    return operation;
  }

  Future<void> _performRestart(String reason) async {
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
    health.record('restart_$reason', attempt: _locationRetryAttempt);
    try {
      await previous?.cancel().timeout(operationTimeout);
    } catch (error) {
      if (_disposed || restartGeneration != _locationStreamGeneration) rethrow;
      _reportError(error);
      _scheduleLocationRetry();
      rethrow;
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
    // A created subscription is not proof of recovery; only callbacks reset it.
    if (reason == 'silence' &&
        restartGeneration + 1 == _locationStreamGeneration &&
        !_disposed &&
        isSharing) {
      _locationRetryAttempt++;
      final seconds = min(300, 30 * (1 << min(_locationRetryAttempt, 4)));
      _nextRecoveryAt = _elapsed + Duration(seconds: seconds);
    }
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
    if (!_isFreshFix(point)) {
      health.record('old_fix_ignored');
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
    final refreshing =
        _refreshRequestedAt != null &&
        !point.timestamp.toUtc().isBefore(_refreshRequestedAt!);
    if (moved >= minDisplacementMeters ||
        elapsed >= maxHeartbeatInterval ||
        refreshing) {
      await _publish(point);
    }
  }

  bool _isFreshFix(LiveLocationPoint point) {
    final age = _clock().toUtc().difference(point.timestamp.toUtc());
    return age <= silenceTimeout && age >= -silenceTimeout;
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
    final generation = _sessionGeneration;
    _writeOwner = generation;
    try {
      final enriched = await _withBattery(
        point,
        threadId: threadId,
        userId: userId,
        recipientUid: _activeRecipientUid,
      );
      if (_disposed || generation != _sessionGeneration || !isSharing) return;
      await _repository
          .updateLocation(
            sessionId: sessionId,
            threadId: threadId,
            userId: userId,
            point: enriched,
          )
          .timeout(writeTimeout);
      if (_disposed || generation != _sessionGeneration || !isSharing) return;
      _lastPublishedPoint = enriched;
      _lastPublishedAt = _clock().toUtc();
      _emitActiveSession(enriched);
      final requested = _refreshRequestedAt;
      final waiter = _freshPublication;
      if (requested != null &&
          !point.timestamp.toUtc().isBefore(requested) &&
          waiter != null &&
          !waiter.isCompleted) {
        waiter.complete();
        health.record('refresh_published');
      }
    } catch (error) {
      if (generation == _sessionGeneration) {
        health.record('publish_failed', error: error);
        _reportError(error);
      }
    } finally {
      if (_writeOwner == generation) {
        _writeInFlight = false;
        _writeOwner = null;
      }
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
    final generation = _sessionGeneration;
    final BatteryStatus? status;
    try {
      status = await reader.read().timeout(
        _batteryReadTimeout,
        onTimeout: () => null,
      );
    } catch (error) {
      _reportError(error);
      return point;
    }
    if (status == null || generation != _sessionGeneration || _disposed) {
      return point;
    }

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
          if (generation == _sessionGeneration) _lowBatteryNotified = false;
          _reportError(error);
        }),
      );
    }
    return point.withBattery(level: status.level, charging: status.charging);
  }

  Future<void> stopSharing() async {
    final threadId = _activeThreadId;
    final userId = _activeUserId;
    final sessionId = _activeSessionId;
    _sessionGeneration++;
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    _healthTimer?.cancel();
    _healthTimer = null;
    _locationStreamGeneration++;
    _restartOperation = null;
    _refreshOperation = null;
    final waiter = _freshPublication;
    _freshPublication = null;
    _refreshRequestedAt = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('Live location sharing stopped.'));
    }
    _pendingRefresh = null;
    _handlingRefresh = false;
    _writeOwner = null;
    _writeInFlight = false;
    final refreshSubscription = _refreshRequestSubscription;
    _refreshRequestSubscription = null;
    final subscription = _positionSubscription;
    _positionSubscription = null;
    _clearActiveSession();
    health.record('stopped');
    await _forgetPersisted();
    Object? failure;
    for (final previous in [refreshSubscription, subscription]) {
      try {
        await previous?.cancel().timeout(operationTimeout);
      } catch (error) {
        failure ??= error;
        _reportError(error);
      }
    }
    if (threadId != null && userId != null && sessionId != null) {
      try {
        await _repository
            .stopSession(
              sessionId: sessionId,
              threadId: threadId,
              userId: userId,
            )
            .timeout(writeTimeout);
      } catch (error) {
        health.record('remote_stop_failed', error: error);
        failure ??= error;
        _reportError(error);
      }
    }
    if (failure != null) throw failure;
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
    final lastFix = _lastFreshFixAt;
    final started = _subscriptionStartedAt;
    if (_positionSubscription != null &&
        _locationRetryTimer == null &&
        lastFix != null &&
        (started == null || lastFix >= started) &&
        _elapsed - lastFix < silenceTimeout) {
      return;
    }
    await _recoverSafely('resume');
  }

  void _reportError(Object error) {
    health.record('error', error: error);
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
    if (!_activeSessionController.isClosed) _activeSessionController.add(null);
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
            altitude: fix.altitude,
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
    _sessionGeneration++;
    _healthTimer?.cancel();
    _healthTimer = null;
    final waiter = _freshPublication;
    _freshPublication = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('LiveLocationService is disposed.'));
    }
    health.record('disposed');
    WidgetsBinding.instance.removeObserver(this);
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    _locationRetryTimer?.cancel();
    _locationRetryTimer = null;
    _locationStreamGeneration++;
    unawaited(
      _positionSubscription?.cancel().timeout(operationTimeout).catchError((
        Object error,
      ) {
        _reportError(error);
      }),
    );
    _positionSubscription = null;
    unawaited(
      _refreshRequestSubscription
          ?.cancel()
          .timeout(operationTimeout)
          .catchError((Object error) {
            _reportError(error);
          }),
    );
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
