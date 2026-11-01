import 'dart:async';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../../core/location/app_location.dart';
import '../../../../core/location/location_source.dart';

import '../../domain/entities/live_location.dart';
import '../../domain/repositories/live_location_repository.dart';
import 'device_battery.dart';

typedef LiveLocationUpdates = Stream<LiveLocationPoint> Function();

/// Tells the partner the sharer's battery is low. Sent once per session.
typedef LowBatteryNotifier =
    Future<void> Function({
      required String threadId,
      required String senderId,
      required String recipientUid,
      required int level,
    });

/// Owns a single active Android live-location session and its GPS subscription.
class LiveLocationService {
  LiveLocationService({
    required LiveLocationRepository repository,
    LiveLocationUpdates? locationUpdates,
    DateTime Function()? clock,
    BatteryReader? battery,
    LowBatteryNotifier? onLowBattery,
  }) : _repository = repository,
       _locationUpdates =
           locationUpdates ?? LiveLocationService._geolocatorUpdates,
       _clock = clock ?? DateTime.now,
       _battery = battery,
       _onLowBattery = onLowBattery;

  final LiveLocationRepository _repository;
  final LiveLocationUpdates _locationUpdates;
  final DateTime Function() _clock;
  final BatteryReader? _battery;
  final LowBatteryNotifier? _onLowBattery;
  final _uuid = const Uuid();

  Timer? _sessionExpiryTimer;
  StreamSubscription<LiveLocationPoint>? _positionSubscription;
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
    _lastPublishedPoint = firstPoint;
    _lastPublishedAt = now;
    _emitActiveSession(firstPoint);

    _sessionExpiryTimer = Timer(duration, () {
      unawaited(_stopAfterExpiry());
    });
    _positionSubscription = _locationUpdates().listen(
      (point) => unawaited(_handleLocation(point)),
      onError: (Object error, StackTrace stackTrace) {
        _reportError(error);
      },
    );
    return sessionId;
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
    final status = await reader.read();
    if (status == null) return point;

    final low = !status.charging && status.level <= lowBatteryThreshold;
    final notify = _onLowBattery;
    if (!low) {
      _lowBatteryNotified = false;
    } else if (!_lowBatteryNotified && notify != null && recipientUid != null) {
      _lowBatteryNotified = true;
      try {
        await notify(
          threadId: threadId,
          senderId: userId,
          recipientUid: recipientUid,
          level: status.level,
        );
      } catch (error) {
        _lowBatteryNotified = false;
        _reportError(error);
      }
    }
    return point.withBattery(level: status.level, charging: status.charging);
  }

  Future<void> stopSharing() async {
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    await _positionSubscription?.cancel();
    _positionSubscription = null;

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

  static Stream<LiveLocationPoint> _geolocatorUpdates() {
    return AppLocation.instance
        .updates(
          LocationUpdateConfig(
            distanceFilterMeters: minDisplacementMeters.round(),
            interval: minWriteInterval,
            backgroundNotification: true,
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
    _sessionExpiryTimer?.cancel();
    _sessionExpiryTimer = null;
    unawaited(_positionSubscription?.cancel());
    _positionSubscription = null;
    _activeSessionController.close();
    _errorController.close();
  }
}
