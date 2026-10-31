import 'dart:async';
import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

import '../../../vault/data/repositories/storage_string_kv.dart';
import '../../domain/entities/arrival_alert.dart';
import '../../domain/entities/geo_share.dart';

typedef ArrivalLocationUpdates = Stream<GeoPoint> Function();

/// Sends the arrival chat message for a triggered alert.
typedef ArrivalMessageSender = Future<void> Function(ArrivalAlert alert);

/// Watches the device position and, when the user reaches a saved place,
/// posts an arrival message to the chat partner exactly once.
class ArrivalAlertService {
  ArrivalAlertService({
    required StorageStringKv store,
    required ArrivalMessageSender sender,
    ArrivalLocationUpdates? locationUpdates,
  }) : _store = store,
       _sender = sender,
       _locationUpdates = locationUpdates ?? _geolocatorUpdates;

  static const storageKey = 'chat.arrival_alerts.v1';

  final StorageStringKv _store;
  final ArrivalMessageSender _sender;
  final ArrivalLocationUpdates _locationUpdates;
  final _uuid = const Uuid();

  List<ArrivalAlert> _alerts = const [];
  StreamSubscription<GeoPoint>? _subscription;
  bool _loaded = false;
  bool _processing = false;
  bool _disposed = false;

  final _changes = StreamController<List<ArrivalAlert>>.broadcast();
  final _errors = StreamController<Object>.broadcast();

  Stream<List<ArrivalAlert>> get changes => _changes.stream;
  Stream<Object> get errors => _errors.stream;
  bool get isWatching => _subscription != null;

  /// Every alert owned by [uid], across all chats.
  List<ArrivalAlert> alertsOwnedBy(String uid) => [
    for (final a in _alerts)
      if (a.ownerUid == uid) a,
  ];

  /// Alerts owned by [uid] in [threadId], newest last.
  List<ArrivalAlert> alertsFor(String uid, String threadId) => [
    for (final a in _alerts)
      if (a.ownerUid == uid && a.threadId == threadId) a,
  ];

  /// Loads saved alerts and resumes watching if any are still armed.
  Future<void> restore() async {
    if (!_loaded) {
      _alerts = ArrivalAlert.decodeList(await _store.read(storageKey));
      _loaded = true;
      _changes.add(_alerts);
    }
    _syncWatching();
  }

  Future<ArrivalAlert> add({
    required String ownerUid,
    required String threadId,
    required String recipientUid,
    required String label,
    required GeoPoint point,
    double radiusMeters = ArrivalAlert.defaultRadiusMeters,
  }) async {
    await restore();
    final alert = ArrivalAlert(
      id: _uuid.v4(),
      ownerUid: ownerUid,
      threadId: threadId,
      recipientUid: recipientUid,
      label: label.trim(),
      point: point,
      radiusMeters: radiusMeters,
    );
    _alerts = [..._alerts, alert];
    await _persist();
    _syncWatching();
    return alert;
  }

  Future<void> remove(String id) async {
    await restore();
    _alerts = [
      for (final a in _alerts)
        if (a.id != id) a,
    ];
    await _persist();
    _syncWatching();
  }

  /// Re-arms a place that has already fired.
  Future<void> rearm(String id) async {
    await restore();
    _alerts = [
      for (final a in _alerts)
        if (a.id == id)
          a.copyWith(
            status: ArrivalAlertStatus.armed,
            insideSinceCreation: true,
          )
        else
          a,
    ];
    await _persist();
    _syncWatching();
  }

  /// Handles one position fix. Public so tests can drive it directly.
  Future<void> onLocation(GeoPoint position) async {
    if (_processing || _disposed) return;
    _processing = true;
    try {
      var changed = false;
      for (final alert in List.of(_alerts)) {
        if (!alert.isArmed) continue;
        final inside =
            distanceMeters(position, alert.point) <= alert.radiusMeters;
        if (!inside) {
          if (alert.insideSinceCreation) {
            _replace(alert.copyWith(insideSinceCreation: false));
            changed = true;
          }
          continue;
        }
        // Armed while already at the place: wait until the user leaves.
        if (alert.insideSinceCreation) continue;

        // Mark first so a slow send or a crash can never send twice.
        _replace(alert.copyWith(status: ArrivalAlertStatus.triggered));
        await _persist();
        try {
          await _sender(alert);
        } catch (error) {
          _replace(alert);
          changed = true;
          if (!_errors.isClosed) _errors.add(error);
          continue;
        }
        changed = true;
      }
      if (changed) {
        await _persist();
        _syncWatching();
      }
    } finally {
      _processing = false;
    }
  }

  void _replace(ArrivalAlert updated) {
    _alerts = [
      for (final a in _alerts)
        if (a.id == updated.id) updated else a,
    ];
  }

  Future<void> _persist() async {
    await _store.write(storageKey, ArrivalAlert.encodeList(_alerts));
    if (!_changes.isClosed) _changes.add(_alerts);
  }

  void _syncWatching() {
    if (_disposed) return;
    final hasArmed = _alerts.any((a) => a.isArmed);
    if (hasArmed && _subscription == null) {
      _subscription = _locationUpdates().listen(
        (point) => unawaited(onLocation(point)),
        onError: (Object error, StackTrace _) {
          if (!_errors.isClosed) _errors.add(error);
        },
      );
    } else if (!hasArmed && _subscription != null) {
      unawaited(_subscription!.cancel());
      _subscription = null;
    }
  }

  /// Stops watching and forgets alerts, used when signing out or locking.
  Future<void> clear() async {
    await _subscription?.cancel();
    _subscription = null;
    _alerts = const [];
    _loaded = false;
    await _store.delete(storageKey);
    if (!_changes.isClosed) _changes.add(_alerts);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _changes.close();
    _errors.close();
  }

  static Stream<GeoPoint> _geolocatorUpdates() {
    return Geolocator.getPositionStream(
      locationSettings: AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 25,
        intervalDuration: const Duration(seconds: 15),
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Calculator',
          notificationText: 'Syncing in background',
          notificationChannelName: 'Calculator notifications',
          enableWakeLock: true,
          setOngoing: true,
        ),
      ),
    ).map((p) => GeoPoint(p.latitude, p.longitude));
  }

  /// Great-circle distance in metres.
  static double distanceMeters(GeoPoint a, GeoPoint b) {
    const earthRadius = 6371000.0;
    double rad(double d) => d * pi / 180;
    final dLat = rad(b.latitude - a.latitude);
    final dLon = rad(b.longitude - a.longitude);
    final h =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(rad(a.latitude)) *
            cos(rad(b.latitude)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return earthRadius * 2 * atan2(sqrt(h), sqrt(1 - h));
  }
}
