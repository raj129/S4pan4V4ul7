import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/live_location.dart';
import '../../domain/repositories/live_location_repository.dart';

typedef LiveLocationUpdates = Stream<LiveLocationPoint> Function();

/// Owns a single active Android live-location session and its GPS subscription.
class LiveLocationService {
  LiveLocationService({
    required LiveLocationRepository repository,
    LiveLocationUpdates? locationUpdates,
    DateTime Function()? clock,
  }) : _repository = repository,
       _locationUpdates =
           locationUpdates ?? LiveLocationService._geolocatorUpdates,
       _clock = clock ?? DateTime.now;

  final LiveLocationRepository _repository;
  final LiveLocationUpdates _locationUpdates;
  final DateTime Function() _clock;
  final _uuid = const Uuid();

  Timer? _sessionExpiryTimer;
  StreamSubscription<LiveLocationPoint>? _positionSubscription;
  LiveLocationPoint? _lastPublishedPoint;
  DateTime? _lastPublishedAt;
  DateTime? _activeStartedAt;
  String? _activeThreadId;
  String? _activeUserId;
  String? _activeSessionId;
  DateTime? _activeExpiresAt;
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

  Future<String> startSharing({
    required String threadId,
    required String userId,
    required Duration duration,
    required LiveLocationPoint initialPoint,
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
    final startWrite = _repository.startSession(
      sessionId: sessionId,
      threadId: threadId,
      userId: userId,
      duration: duration,
      initialPoint: initialPoint,
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
    _activeSessionId = sessionId;
    _activeStartedAt = now;
    _activeExpiresAt = expiresAt;
    _lastPublishedPoint = initialPoint;
    _lastPublishedAt = now;
    _emitActiveSession(initialPoint);

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
      await _repository
          .updateLocation(
            sessionId: sessionId,
            threadId: threadId,
            userId: userId,
            point: point,
          )
          .timeout(writeTimeout);
      _lastPublishedPoint = point;
      _lastPublishedAt = _clock().toUtc();
      _emitActiveSession(point);
    } catch (error) {
      _reportError(error);
    } finally {
      _writeInFlight = false;
    }
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
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: minDisplacementMeters.round(),
        intervalDuration: minWriteInterval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Live location is being shared',
          notificationText: 'Your location is shared in an encrypted chat.',
          notificationChannelName: 'Live location sharing',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).map(
      (position) => LiveLocationPoint(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
        heading: position.heading,
        speed: position.speed,
        timestamp: position.timestamp.toUtc(),
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
