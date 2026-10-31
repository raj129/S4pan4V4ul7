import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/services/arrival_alert_service.dart';
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

  group('ArrivalAlertService', () {
    late _MemoryKv kv;
    late List<ArrivalAlert> sent;
    late ArrivalAlertService service;
    final stream = StreamController<GeoPoint>.broadcast();

    setUp(() {
      kv = _MemoryKv();
      sent = [];
      service = ArrivalAlertService(
        store: kv,
        sender: (alert) async => sent.add(alert),
        locationUpdates: () => stream.stream,
      );
    });

    tearDown(() => service.dispose());

    Future<void> addPlace(String label, GeoPoint point) => service.add(
      ownerUid: 'me',
      threadId: 'me_you',
      recipientUid: 'you',
      label: label,
      point: point,
    );

    test('fires once per place when each is reached', () async {
      await addPlace('Cafe', const GeoPoint(10, 10));
      await addPlace('Office', const GeoPoint(20, 20));

      await service.onLocation(const GeoPoint(0, 0));
      expect(sent, isEmpty);

      await service.onLocation(const GeoPoint(10.0001, 10.0001));
      await service.onLocation(const GeoPoint(10.0002, 10.0002));
      expect(sent.map((a) => a.label), ['Cafe']);

      await service.onLocation(const GeoPoint(20, 20));
      expect(sent.map((a) => a.label), ['Cafe', 'Office']);
      expect(service.isWatching, isFalse);
    });

    test('persists alerts and restores them', () async {
      await addPlace('Cafe', const GeoPoint(10, 10));
      final restored = ArrivalAlertService(
        store: kv,
        sender: (_) async {},
        locationUpdates: () => stream.stream,
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.alertsFor('me', 'me_you'), hasLength(1));
      expect(restored.isWatching, isTrue);
    });

    test('keeps the alert armed when sending fails', () async {
      final failing = ArrivalAlertService(
        store: _MemoryKv(),
        sender: (_) async => throw StateError('offline'),
        locationUpdates: () => stream.stream,
      );
      addTearDown(failing.dispose);
      final errors = <Object>[];
      failing.errors.listen(errors.add);
      await failing.add(
        ownerUid: 'me',
        threadId: 't',
        recipientUid: 'you',
        label: 'Cafe',
        point: const GeoPoint(10, 10),
      );
      await failing.onLocation(const GeoPoint(10, 10));
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(failing.alertsFor('me', 't').single.isArmed, isTrue);
    });

    test('computes great-circle distance', () {
      final d = ArrivalAlertService.distanceMeters(
        const GeoPoint(0, 0),
        const GeoPoint(0, 1),
      );
      expect(d, closeTo(111195, 100));
    });
  });
}
