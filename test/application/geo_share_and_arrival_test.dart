import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/services/arrival_alert_service.dart';
import 'package:photo_vault/features/chat/application/services/arrival_geofences.dart';
import 'package:photo_vault/features/chat/application/services/directions_service.dart';
import 'package:photo_vault/features/chat/application/services/saved_places_service.dart';
import 'package:photo_vault/features/chat/domain/entities/arrival_alert.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/geo_share.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_string_kv.dart';

class _MemoryKv implements StorageStringKv {
  final values = <String, String>{};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

class _FakeFences implements ArrivalGeofences {
  final List<List<ArrivalFence>> syncs = [];
  List<ArrivalGeofenceEvent> pending = [];
  final List<String> acked = [];
  Object? syncError;

  @override
  Future<void> sync(List<ArrivalFence> fences) async {
    if (syncError != null) throw syncError!;
    syncs.add(fences);
  }

  @override
  Future<List<ArrivalGeofenceEvent>> peekPending() async => List.of(pending);

  @override
  Future<void> ackPending(List<String> eids) async {
    acked.addAll(eids);
    pending = [
      for (final e in pending)
        if (!eids.contains(e.eid)) e,
    ];
  }

  List<String> get lastFenceIds => [for (final f in syncs.last) f.id];
}

void main() {
  group('GeoShare', () {
    test('round-trips a route', () {
      const route = GeoShare.route(
        origin: GeoPoint(1, 2),
        destination: GeoPoint(3, 4),
        label: 'Home',
        path: [GeoPoint(1, 2), GeoPoint(3, 4)],
        distanceMeters: 1500,
        durationSeconds: 600,
      );
      expect(GeoShare.tryDecode(route.encode()), route);
    });

    test('rejects text that is not a location payload', () {
      expect(GeoShare.tryDecode('hello'), isNull);
      expect(GeoShare.tryDecode('{"k":"pin"}'), isNull);
    });

    test('geo messages expose a readable preview, not raw JSON', () {
      final message = ChatMessage(
        messageId: 'm',
        threadId: 't',
        senderId: 'a',
        encryptedText: '',
        sentAt: DateTime.utc(2026),
        deletedFor: const [],
        mediaType: MessageType.arrival,
        localDecryptedText: const GeoShare.arrival(
          point: GeoPoint(1, 2),
          label: 'Office',
        ).encode(),
      );
      expect(message.mediaPreview, '✅ I have reached Office');
      expect(message.hasMediaSlot, isFalse);
    });
  });

  group('DirectionsService', () {
    test('decodes a Google encoded polyline', () {
      final points = DirectionsService.decodePolyline('_p~iF~ps|U_ulLnnqC');
      expect(points, hasLength(2));
      expect(points.first.latitude, closeTo(38.5, 1e-6));
      expect(points.first.longitude, closeTo(-120.2, 1e-6));
    });

    test('falls back to a straight line without an API key', () async {
      final service = DirectionsService(apiKey: '');
      final route = await service.fetchRoute(
        origin: const GeoPoint(0, 0),
        destination: const GeoPoint(1, 1),
      );
      expect(route.path, hasLength(2));
      expect(route.isRoute, isTrue);
    });
  });

  group('SavedPlacesService', () {
    test('stores places per owner and survives a reload', () async {
      final kv = _MemoryKv();
      final service = SavedPlacesService(store: kv);
      await service.add(
        ownerUid: 'me',
        label: ' Home ',
        point: const GeoPoint(1, 2),
      );
      await service.add(
        ownerUid: 'other',
        label: 'Elsewhere',
        point: const GeoPoint(3, 4),
      );

      final reloaded = SavedPlacesService(store: kv);
      final mine = await reloaded.placesFor('me');
      expect(mine.map((p) => p.label), ['Home']);

      await reloaded.remove(mine.single.id);
      expect(await reloaded.placesFor('me'), isEmpty);
      await service.clear();
      expect(kv.values, isEmpty);
    });
  });

  group('places', () {
    test('lists frequent places first and hides expired temporary ones', () async {
      var now = DateTime.utc(2026, 11, 1);
      final places = SavedPlacesService(store: _MemoryKv(), clock: () => now);
      await places.add(ownerUid: 'me', label: 'Cafe', point: const GeoPoint(1, 1));
      final gym = await places.add(ownerUid: 'me', label: 'Gym', point: const GeoPoint(2, 2));
      await places.recordVisit(gym.id);
      await places.recordVisit(gym.id);
      await places.add(
        ownerUid: 'me',
        label: 'Temp',
        point: const GeoPoint(3, 3),
        temporary: true,
      );
      expect((await places.placesFor('me')).map((p) => p.label), ['Gym', 'Cafe', 'Temp']);

      now = now.add(const Duration(hours: 25));
      expect((await places.placesFor('me')).map((p) => p.label), ['Gym', 'Cafe']);
      await places.purgeExpired();
      expect((await places.placesFor('me')).map((p) => p.label), ['Gym', 'Cafe']);
    });

    test('keeping a temporary place makes it a saved place', () async {
      final places = SavedPlacesService(store: _MemoryKv());
      final temp = await places.add(
        ownerUid: 'me',
        label: 'Office',
        point: const GeoPoint(1, 1),
        temporary: true,
      );
      final kept = await places.update(temp.id, keep: true);
      expect(kept?.temporary, isFalse);
      expect(kept?.expiresAt, isNull);
    });

    test('cancelling an alert deletes its temporary place but not a saved one', () async {
      final kv = _MemoryKv();
      final places = SavedPlacesService(store: kv);
      final temp = await places.add(
        ownerUid: 'me',
        label: 'Temp',
        point: const GeoPoint(10, 10),
        temporary: true,
      );
      final saved = await places.add(
        ownerUid: 'me',
        label: 'Home',
        point: const GeoPoint(20, 20),
      );
      final alerts = ArrivalAlertService(
        store: kv,
        sender: (_) async {},
        geofences: _FakeFences(),
        places: places,
      );
      addTearDown(alerts.dispose);

      final tempAlert = await alerts.add(
        ownerUid: 'me',
        threadId: 't',
        recipientUid: 'you',
        label: 'Temp',
        point: temp.point,
        placeId: temp.id,
      );
      final savedAlert = await alerts.add(
        ownerUid: 'me',
        threadId: 't',
        recipientUid: 'you',
        label: 'Home',
        point: saved.point,
        placeId: saved.id,
      );
      await alerts.remove(tempAlert.id);
      await alerts.remove(savedAlert.id);

      expect((await places.placesFor('me')).map((p) => p.label), ['Home']);
    });
  });

  group('ArrivalAlertService', () {
    late _MemoryKv kv;
    late List<ArrivalAlert> sent;
    late _FakeFences fences;
    late ArrivalAlertService service;

    setUp(() {
      kv = _MemoryKv();
      sent = [];
      fences = _FakeFences();
      service = ArrivalAlertService(
        store: kv,
        sender: (alert) async => sent.add(alert),
        geofences: fences,
      );
    });

    tearDown(() => service.dispose());

    Future<ArrivalAlert> addPlace(String label, GeoPoint point) => service.add(
      ownerUid: 'me',
      threadId: 'me_you',
      recipientUid: 'you',
      label: label,
      point: point,
    );

    var eventCount = 0;
    ArrivalGeofenceEvent event(
      String alertId, {
      double? lat,
      double? lng,
      DateTime? at,
    }) => ArrivalGeofenceEvent(
      eid: 'event-${eventCount++}',
      alertId: alertId,
      enqueuedAt: at ?? DateTime.now(),
      latitude: lat,
      longitude: lng,
    );

    /// Queues [events] as if the native receiver had recorded them, then processes.
    Future<bool> deliver(List<ArrivalGeofenceEvent> events) async {
      fences.pending = events;
      return service.processPendingArrivals();
    }

    test('arms every saved alert as soon as it is saved', () async {
      await addPlace('Cafe', const GeoPoint(10, 10));
      expect(fences.lastFenceIds, hasLength(1));
      expect(fences.syncs.last.single.radiusMeters, 100);
    });

    test('uses the radius chosen when saving', () async {
      await service.add(
        ownerUid: 'me',
        threadId: 'me_you',
        recipientUid: 'you',
        label: 'Home',
        point: const GeoPoint(10, 10),
        radiusMeters: 200,
      );
      expect(fences.syncs.last.single.radiusMeters, 200);
    });

    test('sends once per place and disarms it', () async {
      final cafe = await addPlace('Cafe', const GeoPoint(10, 10));
      final office = await addPlace('Office', const GeoPoint(20, 20));

      await deliver([event(cafe.id)]);
      await deliver([event(cafe.id)]);
      expect(sent.map((a) => a.label), ['Cafe']);
      expect(fences.lastFenceIds, [office.id]);

      await deliver([event(office.id)]);
      expect(sent.map((a) => a.label), ['Cafe', 'Office']);
      expect(fences.syncs.last, isEmpty);
    });

    test('matches every saved place that contains the coordinate', () async {
      final near = await addPlace('Near', const GeoPoint(10, 10));
      await addPlace('Far', const GeoPoint(20, 20));
      // Within 100 m of "Near" only. The enter event names no alert.
      await deliver([event('unknown', lat: 10.0003, lng: 10)]);
      expect(sent.map((a) => a.id), [near.id]);
    });

    test('does not match a place when the coordinate is outside its radius', () async {
      await addPlace('Cafe', const GeoPoint(10, 10));
      await deliver([event('unknown', lat: 10.01, lng: 10)]);
      expect(sent, isEmpty);
    });

    test('acks events for unknown or disarmed alerts without sending', () async {
      final stale = event('missing');
      expect(await deliver([stale]), isTrue);
      expect(sent, isEmpty);
      expect(fences.acked, [stale.eid]);
    });

    test('drops events older than 24 hours', () async {
      final cafe = await addPlace('Cafe', const GeoPoint(10, 10));
      final old = event(
        cafe.id,
        at: DateTime.now().subtract(const Duration(hours: 25)),
      );
      expect(await deliver([old]), isTrue);
      expect(sent, isEmpty);
      expect(fences.acked, [old.eid]);
    });

    test('delivers arrivals queued while the app was closed', () async {
      final cafe = await addPlace('Cafe', const GeoPoint(10, 10));
      fences.pending = [event(cafe.id, lat: 10, lng: 10)];

      expect(await service.refreshArrivals(), isTrue);
      expect(sent.map((a) => a.label), ['Cafe']);
      expect(fences.pending, isEmpty);
    });

    test('a failed send stays queued and is retried', () async {
      var offline = true;
      final retryFences = _FakeFences();
      final retrying = ArrivalAlertService(
        store: _MemoryKv(),
        sender: (alert) async {
          if (offline) throw StateError('offline');
          sent.add(alert);
        },
        geofences: retryFences,
      );
      addTearDown(retrying.dispose);
      final cafe = await retrying.add(
        ownerUid: 'me',
        threadId: 't',
        recipientUid: 'you',
        label: 'Cafe',
        point: const GeoPoint(10, 10),
      );
      retryFences.pending = [event(cafe.id)];

      expect(await retrying.processPendingArrivals(), isFalse);
      expect(retryFences.acked, isEmpty);
      expect(retryFences.pending, hasLength(1));

      offline = false;
      expect(await retrying.processPendingArrivals(), isTrue);
      expect(retryFences.acked, hasLength(1));
      expect(sent.map((a) => a.label), ['Cafe']);
    });

    test('persists alerts and restores them', () async {
      await addPlace('Cafe', const GeoPoint(10, 10));
      final restored = ArrivalAlertService(
        store: kv,
        sender: (_) async {},
        geofences: _FakeFences(),
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.alertsFor('me', 'me_you'), hasLength(1));
    });

    test('exposes a registration failure and clears it on success', () async {
      fences.syncError = PlatformException(
        code: 'geofence_failed',
        message: 'Background location is off.',
      );
      await addPlace('Cafe', const GeoPoint(10, 10));
      expect(service.fenceError, 'Background location is off.');

      fences.syncError = null;
      await addPlace('Office', const GeoPoint(20, 20));
      expect(service.fenceError, isNull);
    });

    test('keeps the alert armed when sending fails', () async {
      final failingFences = _FakeFences();
      final failing = ArrivalAlertService(
        store: _MemoryKv(),
        sender: (_) async => throw StateError('offline'),
        geofences: failingFences,
      );
      addTearDown(failing.dispose);
      final errors = <Object>[];
      failing.errors.listen(errors.add);
      final cafe = await failing.add(
        ownerUid: 'me',
        threadId: 't',
        recipientUid: 'you',
        label: 'Cafe',
        point: const GeoPoint(10, 10),
      );
      failingFences.pending = [
        ArrivalGeofenceEvent(
          eid: 'e1',
          alertId: cafe.id,
          enqueuedAt: DateTime.now(),
        ),
      ];
      expect(await failing.processPendingArrivals(), isFalse);
      await Future<void>.delayed(Duration.zero);
      expect(errors, isNotEmpty);
      expect(failing.alertsFor('me', 't').single.isArmed, isTrue);
    });
  });
}
