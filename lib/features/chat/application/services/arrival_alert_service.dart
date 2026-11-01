import 'dart:async';

import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/location/geo_fix.dart';
import '../../../vault/data/repositories/storage_string_kv.dart';
import '../../domain/entities/arrival_alert.dart';
import '../../domain/entities/geo_share.dart';
import 'arrival_geofences.dart';
import 'saved_places_service.dart';

/// Sends the arrival chat message for a triggered alert.
typedef ArrivalMessageSender = Future<void> Function(ArrivalAlert alert);

/// Sends arrival messages when the device reaches a saved place.
///
/// Every armed alert is registered as an OS geofence as soon as it is saved,
/// so no app-side GPS polling is needed. When an enter event arrives, the
/// queued device coordinate is matched locally against all armed alerts, and
/// each alert whose radius contains it is sent once.
class ArrivalAlertService {
  ArrivalAlertService({
    required StorageStringKv store,
    required ArrivalMessageSender sender,
    ArrivalGeofences? geofences,
    SavedPlacesService? places,
  }) : _store = store,
       _sender = sender,
       _geofences = geofences,
       _places = places;

  static const storageKey = 'chat.arrival_alerts.v1';

  final StorageStringKv _store;
  final ArrivalMessageSender _sender;
  final ArrivalGeofences? _geofences;
  final SavedPlacesService? _places;
  final _uuid = const Uuid();

  List<ArrivalAlert> _alerts = const [];
  bool _loaded = false;
  bool _disposed = false;
  String? _fenceError;

  final _changes = StreamController<List<ArrivalAlert>>.broadcast();
  final _errors = StreamController<Object>.broadcast();

  Stream<List<ArrivalAlert>> get changes => _changes.stream;
  Stream<Object> get errors => _errors.stream;

  /// Why the last geofence registration failed, or null when it succeeded.
  /// Shown on armed alerts so the user knows they will not fire.
  String? get fenceError => _fenceError;

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

  /// Loads saved alerts and registers their geofences.
  Future<void> restore() async {
    if (!_loaded) {
      _alerts = ArrivalAlert.decodeList(await _store.read(storageKey));
      _loaded = true;
      _changes.add(_alerts);
    }
    await _syncFences();
  }

  Future<ArrivalAlert> add({
    required String ownerUid,
    required String threadId,
    required String recipientUid,
    required String label,
    required GeoPoint point,
    double radiusMeters = ArrivalAlert.defaultRadiusMeters,
    String? placeId,
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
      placeId: placeId,
    );
    _alerts = [..._alerts, alert];
    await _persist();
    await _syncFences();
    return alert;
  }

  /// Cancels an alert. A temporary place it was made from is deleted too.
  Future<void> remove(String id) async {
    await restore();
    final removed = _alerts.where((a) => a.id == id);
    final placeId = removed.isEmpty ? null : removed.single.placeId;
    _alerts = [
      for (final a in _alerts)
        if (a.id != id) a,
    ];
    await _persist();
    await _syncFences();
    if (placeId != null) await _places?.removeIfTemporary(placeId);
  }

  /// Re-arms a place that has already fired.
  Future<void> rearm(String id) async {
    await restore();
    _alerts = [
      for (final a in _alerts)
        if (a.id == id) a.copyWith(status: ArrivalAlertStatus.armed) else a,
    ];
    await _persist();
    await _syncFences();
  }

  /// Registers saved places, then delivers arrivals queued while the app was closed.
  Future<bool> refreshArrivals() async {
    await restore();
    return processPendingArrivals();
  }

  /// Events older than this are dropped, so a send that can never succeed
  /// (lost alert, permanently signed out) does not retry forever.
  static const Duration maxEventAge = Duration(hours: 24);

  /// Handles every queued enter event. An event is acked once it is handled:
  /// sent, obsolete, or too old. A failed send stays queued for the next run.
  /// Returns false when some event is still pending after a failure.
  Future<bool> processPendingArrivals() async {
    final geofences = _geofences;
    if (geofences == null || _disposed) return true;
    // Another isolate (the background worker) may have changed the alerts.
    _alerts = ArrivalAlert.decodeList(await _store.read(storageKey));
    _loaded = true;
    final List<ArrivalGeofenceEvent> events;
    try {
      events = await geofences.peekPending();
    } catch (error) {
      if (!_errors.isClosed) _errors.add(error);
      return false;
    }

    final handled = <String>[];
    var allHandled = true;
    final now = DateTime.now();
    for (final event in events) {
      if (now.difference(event.enqueuedAt) > maxEventAge) {
        handled.add(event.eid);
        continue;
      }
      var sent = true;
      final placeIds = <String>[];
      for (final id in _matchingAlertIds(event)) {
        final placeId = _placeIdOf(id);
        if (!await _fire(id)) {
          sent = false;
        } else if (placeId != null) {
          placeIds.add(placeId);
        }
      }
      if (sent) {
        for (final placeId in placeIds) {
          await _places?.recordVisit(placeId);
        }
        handled.add(event.eid);
      } else {
        allHandled = false;
      }
    }

    if (handled.isNotEmpty) {
      try {
        await geofences.ackPending(handled);
      } catch (error) {
        if (!_errors.isClosed) _errors.add(error);
        allHandled = false;
      }
    }
    return allHandled;
  }

  /// The alert the OS reported, plus every armed alert whose radius contains
  /// the device coordinate from the event.
  List<String> _matchingAlertIds(ArrivalGeofenceEvent event) {
    final ids = <String>{event.alertId};
    final lat = event.latitude;
    final lng = event.longitude;
    if (lat != null && lng != null) {
      final at = GeoCoord(lat, lng);
      for (final alert in _alerts) {
        if (!alert.isArmed) continue;
        final centre = GeoCoord(alert.point.latitude, alert.point.longitude);
        if (at.distanceTo(centre) <= alert.radiusMeters) ids.add(alert.id);
      }
    }
    return ids.toList();
  }

  String? _placeIdOf(String alertId) {
    for (final a in _alerts) {
      if (a.id == alertId) return a.placeId;
    }
    return null;
  }

  /// Sends the alert once. Returns false only when the send failed, in which
  /// case the alert is re-armed so a later run can retry it.
  Future<bool> _fire(String alertId) async {
    if (_disposed) return true;
    final matches = _alerts.where((a) => a.id == alertId && a.isArmed);
    if (matches.isEmpty) return true;
    final alert = matches.single;

    // Mark first so a slow send or a crash can never send twice.
    _replace(alert.copyWith(status: ArrivalAlertStatus.triggered));
    await _persist();
    await _syncFences();
    try {
      await _sender(alert);
    } catch (error) {
      _replace(alert);
      await _persist();
      await _syncFences();
      if (!_errors.isClosed) _errors.add(error);
      return false;
    }
    // A temporary place has served its purpose once its alert has fired.
    final placeId = alert.placeId;
    if (placeId != null) await _places?.removeIfTemporary(placeId);
    return true;
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

  /// Registers one geofence per armed alert. A failed registration is kept in
  /// [fenceError] and republished so the UI can show it.
  Future<void> _syncFences() async {
    final geofences = _geofences;
    if (geofences == null || _disposed) return;
    final fences = [
      for (final a in _alerts)
        if (a.isArmed)
          ArrivalFence(
            id: a.id,
            latitude: a.point.latitude,
            longitude: a.point.longitude,
            radiusMeters: a.radiusMeters,
          ),
    ];
    try {
      await geofences.sync(fences);
      _setFenceError(null);
    } catch (error) {
      _setFenceError(_describe(error));
      if (!_errors.isClosed) _errors.add(error);
    }
  }

  void _setFenceError(String? message) {
    if (_fenceError == message) return;
    _fenceError = message;
    if (!_changes.isClosed) _changes.add(_alerts);
  }

  static String _describe(Object error) {
    if (error is PlatformException && error.message != null) {
      return error.message!;
    }
    return 'Could not arm this place. Check location permission is "Allow all the time".';
  }

  /// Stops watching and forgets alerts, used when signing out or locking.
  Future<void> clear() async {
    _alerts = const [];
    _loaded = false;
    await _store.delete(storageKey);
    await _syncFences();
    if (!_changes.isClosed) _changes.add(_alerts);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _changes.close();
    _errors.close();
  }
}
