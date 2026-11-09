import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_vault/core/location/app_location.dart';
import 'package:photo_vault/core/location/geo_fix.dart';
import 'package:photo_vault/core/location/location_source.dart';
import 'package:photo_vault/features/chat/application/services/device_battery.dart';
import 'package:photo_vault/features/chat/application/services/live_location_service.dart';
import 'package:photo_vault/features/chat/domain/entities/live_location.dart';
import 'package:photo_vault/features/chat/domain/repositories/live_location_repository.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_string_kv.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLiveLocationRepository repository;
  late StreamController<LiveLocationPoint> positions;
  late LiveLocationService service;
  var now = DateTime.utc(2026, 10, 21, 12);

  final firstPoint = LiveLocationPoint(
    latitude: 51.5007,
    longitude: -0.1246,
    accuracy: 8,
    timestamp: DateTime.utc(2026, 10, 21, 12),
  );

  setUp(() {
    repository = _FakeLiveLocationRepository();
    positions = StreamController<LiveLocationPoint>.broadcast();
    now = DateTime.utc(2026, 10, 21, 12);
    service = LiveLocationService(
      repository: repository,
      locationUpdates: () => positions.stream,
      clock: () => now,
    );
  });

  tearDown(() async {
    if (service.isSharing) {
      await service.stopSharing();
    }
    service.dispose();
    unawaited(positions.close());
    repository.dispose();
  });

  test(
    'starts a session, publishes initial location, and stops cleanly',
    () async {
      await service.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 15),
        initialPoint: firstPoint,
      );

      expect(service.isSharing, isTrue);
      expect(service.activeThreadId, 'alice_bob');
      expect(repository.started, hasLength(1));
      expect(repository.started.single.initialPoint, firstPoint);
      expect(service.activeSessionId, repository.started.single.sessionId);

      await service.stopSharing();

      expect(service.isSharing, isFalse);
      expect(repository.stopped, [
        (repository.started.single.sessionId, 'alice_bob', 'alice'),
      ]);
    },
  );

  test(
    'publishes after the movement and minimum-interval thresholds',
    () async {
      await service.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 15),
        initialPoint: firstPoint,
      );
      final movedPoint = LiveLocationPoint(
        latitude: firstPoint.latitude + 0.0002,
        longitude: firstPoint.longitude,
        accuracy: 6,
        timestamp: now.add(const Duration(seconds: 11)),
      );

      now = now.add(const Duration(seconds: 11));
      await service.onNewLocation(movedPoint);

      expect(repository.updated, [movedPoint]);
    },
  );

  test('refresh request restarts updates and acknowledges its token', () async {
    final locationStreams = <StreamController<LiveLocationPoint>>[];
    final refreshService = LiveLocationService(
      repository: repository,
      locationUpdates: () {
        final stream = StreamController<LiveLocationPoint>.broadcast();
        locationStreams.add(stream);
        return stream.stream;
      },
      clock: () => now,
    );
    addTearDown(() async {
      if (refreshService.isSharing) await refreshService.stopSharing();
      refreshService.dispose();
      for (final stream in locationStreams) {
        await stream.close();
      }
    });

    await refreshService.startSharing(
      threadId: 'alice_bob',
      userId: 'alice',
      duration: const Duration(minutes: 15),
      initialPoint: firstPoint,
    );
    expect(locationStreams, hasLength(1));

    now = now.add(const Duration(seconds: 91));
    repository.refreshRequests.add(
      LiveLocationRefreshRequest(
        requestToken: 'request-1',
        requestedBy: 'bob',
        requestedAt: now,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(locationStreams, hasLength(2));
    final refreshedPoint = LiveLocationPoint(
      latitude: firstPoint.latitude,
      longitude: firstPoint.longitude,
      accuracy: firstPoint.accuracy,
      timestamp: now,
    );
    locationStreams.last.add(refreshedPoint);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(repository.updated, [refreshedPoint]);
    expect(repository.acknowledgedRefreshRequests, [
      ('request-1', 'alice_bob', repository.started.last.sessionId),
    ]);
  });

  test('manual refresh is rejected after sharing stops', () async {
    await service.startSharing(
      threadId: 'alice_bob',
      userId: 'alice',
      duration: const Duration(minutes: 15),
      initialPoint: firstPoint,
    );
    await service.stopSharing();

    await expectLater(service.refreshSharing(), throwsStateError);
  });

  test('publishes a heartbeat while the device is stationary', () async {
    await service.startSharing(
      threadId: 'alice_bob',
      userId: 'alice',
      duration: const Duration(minutes: 15),
      initialPoint: firstPoint,
    );

    now = now.add(const Duration(seconds: 45));
    await service.onNewLocation(
      LiveLocationPoint(
        latitude: firstPoint.latitude,
        longitude: firstPoint.longitude,
        accuracy: firstPoint.accuracy,
        timestamp: now,
      ),
    );

    expect(repository.updated, hasLength(1));
    expect(repository.updated.single.latitude, firstPoint.latitude);
  });

  test(
    'keeps stationary location fixes enabled for heartbeat checks',
    () async {
      final previousLocation = AppLocation.instance;
      final locationSource = _CapturingLocationSource();
      final settings = InMemorySettingsRepository();
      await settings.setBackgroundLocationAlertTitle('Hidden');
      await settings.setBackgroundLocationAlertText('Location active');
      AppLocation.instance = AppLocation(real: locationSource);
      final configured = LiveLocationService(
        repository: repository,
        settingsRepository: settings,
        clock: () => now,
      );

      try {
        await configured.startSharing(
          threadId: 'alice_bob',
          userId: 'alice',
          duration: const Duration(minutes: 15),
          initialPoint: firstPoint,
        );

        expect(locationSource.config?.distanceFilterMeters, 0);
        expect(
          locationSource.config?.interval,
          LiveLocationService.minWriteInterval,
        );
        expect(locationSource.config?.backgroundNotification, isTrue);
        expect(locationSource.config?.notificationTitle, 'Hidden');
        expect(locationSource.config?.notificationText, 'Location active');
        await configured.stopSharing();
      } finally {
        configured.dispose();
        AppLocation.instance = previousLocation;
      }
    },
  );

  test(
    'retries interrupted streams and resumes without restarting stopped sessions',
    () async {
      final streams = <StreamController<LiveLocationPoint>>[];
      final recovering = LiveLocationService(
        repository: repository,
        locationUpdates: () {
          final stream = StreamController<LiveLocationPoint>();
          streams.add(stream);
          return stream.stream;
        },
        clock: () => now,
      );
      addTearDown(recovering.dispose);

      await recovering.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 15),
        initialPoint: firstPoint,
      );
      expect(streams, hasLength(1));

      streams.single.addError(StateError('location service interrupted'));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(streams, hasLength(2));

      recovering.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(streams, hasLength(3));

      await streams[2].close();
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      expect(streams, hasLength(4));

      await recovering.stopSharing();
      recovering.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(streams, hasLength(4));
      await Future.wait(streams.map((stream) => stream.close()));
    },
  );

  test('stops instead of resuming after the session expires', () async {
    final streams = <StreamController<LiveLocationPoint>>[];
    final expiring = LiveLocationService(
      repository: repository,
      locationUpdates: () {
        final stream = StreamController<LiveLocationPoint>();
        streams.add(stream);
        return stream.stream;
      },
      clock: () => now,
    );
    addTearDown(expiring.dispose);

    await expiring.startSharing(
      threadId: 'alice_bob',
      userId: 'alice',
      duration: const Duration(minutes: 1),
      initialPoint: firstPoint,
    );
    now = expiring.activeExpiresAt!;
    expiring.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    expect(expiring.isSharing, isFalse);
    expect(repository.stopped, hasLength(1));
    expect(streams, hasLength(1));
    await Future.wait(streams.map((stream) => stream.close()));
  });

  test(
    'does not publish tiny movement before the heartbeat interval',
    () async {
      await service.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 15),
        initialPoint: firstPoint,
      );
      final movedPoint = LiveLocationPoint(
        latitude: firstPoint.latitude + 0.00001,
        longitude: firstPoint.longitude,
        accuracy: 6,
        timestamp: now.add(const Duration(seconds: 11)),
      );

      now = now.add(const Duration(seconds: 11));
      await service.onNewLocation(movedPoint);

      expect(repository.updated, isEmpty);
    },
  );

  test('rejects sessions longer than eight hours', () async {
    expect(
      const Duration(
        hours: 9,
      ).compareTo(LiveLocationService.maxSessionDuration),
      greaterThan(0),
    );
    Object? failure;
    try {
      await service.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(hours: 9),
        initialPoint: firstPoint,
      );
    } catch (error) {
      failure = error;
    }
    expect(failure, isA<ArgumentError>());
    expect(repository.started, isEmpty);
  });

  test('LiveLocationSession retains last known coordinates when ended or expired', () {
    final stoppedAt = DateTime.utc(2026, 10, 21, 11, 12);
    final session = LiveLocationSession(
      sessionId: 'session_1',
      threadId: 'alice_bob',
      userId: 'alice',
      isActive: false,
      startedAt: DateTime.utc(2026, 10, 21, 11),
      expiresAt: DateTime.utc(2026, 10, 21, 11, 15),
      lastUpdatedAt: DateTime.utc(2026, 10, 21, 11, 10),
      currentPoint: firstPoint,
      stoppedAt: stoppedAt,
    );

    expect(session.isActive, isFalse);
    expect(session.isLive, isFalse);
    expect(session.currentPoint, equals(firstPoint));
    expect(session.stoppedAt, stoppedAt);
  });

  group('restore after the app process was stopped', () {
    test('re-attaches to an unexpired session and publishes again', () async {
      final kv = _MemoryKv();
      final first = LiveLocationService(
        repository: repository,
        locationUpdates: () => positions.stream,
        clock: () => now,
        store: kv,
      );
      await first.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 15),
        initialPoint: firstPoint,
        recipientUid: 'bob',
      );
      final sessionId = first.activeSessionId;
      // Simulates the process being killed: no stopSharing, no dispose.

      final restarted = LiveLocationService(
        repository: repository,
        locationUpdates: () => positions.stream,
        clock: () => now,
        store: kv,
      );
      addTearDown(() async {
        if (restarted.isSharing) await restarted.stopSharing();
        restarted.dispose();
        first.dispose();
      });

      await restarted.restore();

      expect(restarted.isSharing, isTrue);
      expect(restarted.activeSessionId, sessionId);
      expect(restarted.activeThreadId, 'alice_bob');

      now = now.add(const Duration(seconds: 11));
      final moved = LiveLocationPoint(
        latitude: firstPoint.latitude + 0.0002,
        longitude: firstPoint.longitude,
        accuracy: 6,
        timestamp: now,
      );
      await restarted.onNewLocation(moved);
      expect(repository.updated, [moved]);
      expect(repository.updated.last.latitude, moved.latitude);
    });

    test('does not restore an expired session and clears it', () async {
      final kv = _MemoryKv();
      final first = LiveLocationService(
        repository: repository,
        locationUpdates: () => positions.stream,
        clock: () => now,
        store: kv,
      );
      await first.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 1),
        initialPoint: firstPoint,
      );

      now = now.add(const Duration(minutes: 2));
      final restarted = LiveLocationService(
        repository: repository,
        locationUpdates: () => positions.stream,
        clock: () => now,
        store: kv,
      );
      addTearDown(restarted.dispose);

      await restarted.restore();

      expect(restarted.isSharing, isFalse);
      expect(await kv.read(LiveLocationService.storageKey), isNull);
      first.dispose();
    });

    test('a user-stopped session is not restored', () async {
      final kv = _MemoryKv();
      final first = LiveLocationService(
        repository: repository,
        locationUpdates: () => positions.stream,
        clock: () => now,
        store: kv,
      );
      await first.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 15),
        initialPoint: firstPoint,
      );
      await first.stopSharing();

      final restarted = LiveLocationService(
        repository: repository,
        locationUpdates: () => positions.stream,
        clock: () => now,
        store: kv,
      );
      addTearDown(restarted.dispose);

      await restarted.restore();

      expect(restarted.isSharing, isFalse);
      first.dispose();
    });

    test('a hanging battery read does not stop location publishing', () async {
      final battery = _HangingBattery();
      final hanging = LiveLocationService(
        repository: repository,
        locationUpdates: () => positions.stream,
        clock: () => now,
        battery: battery,
        batteryReadTimeout: const Duration(milliseconds: 20),
      );
      addTearDown(hanging.dispose);

      await hanging.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 15),
        initialPoint: firstPoint,
      );

      battery.hang = true;
      now = now.add(const Duration(seconds: 11));
      await hanging.onNewLocation(
        LiveLocationPoint(
          latitude: firstPoint.latitude + 0.0002,
          longitude: firstPoint.longitude,
          accuracy: 6,
          timestamp: now,
        ),
      );
      expect(repository.updated, hasLength(1));

      now = now.add(const Duration(seconds: 11));
      await hanging.onNewLocation(
        LiveLocationPoint(
          latitude: firstPoint.latitude + 0.0004,
          longitude: firstPoint.longitude,
          accuracy: 6,
          timestamp: now,
        ),
      );
      expect(repository.updated, hasLength(2));
      await hanging.stopSharing();
    });
  });

  group('battery', () {
    test('adds battery to published points and notifies partner once when low', () async {
      final notices = <(String, String, String, int)>[];
      final battery = _FakeBattery(const BatteryStatus(level: 14, charging: false));
      final lowService = LiveLocationService(
        repository: repository,
        locationUpdates: () => positions.stream,
        clock: () => now,
        battery: battery,
        onLowBattery: ({
          required threadId,
          required senderId,
          required recipientUid,
          required level,
        }) async {
          notices.add((threadId, senderId, recipientUid, level));
        },
      );
      addTearDown(lowService.dispose);

      await lowService.startSharing(
        threadId: 'alice_bob',
        userId: 'alice',
        duration: const Duration(minutes: 15),
        initialPoint: firstPoint,
        recipientUid: 'bob',
      );
      expect(repository.started.single.initialPoint.batteryLevel, 14);
      expect(repository.started.single.initialPoint.charging, isFalse);

      now = now.add(const Duration(seconds: 11));
      await lowService.onNewLocation(
        LiveLocationPoint(
          latitude: firstPoint.latitude + 0.0002,
          longitude: firstPoint.longitude,
          accuracy: 6,
          timestamp: now,
        ),
      );
      expect(notices, [('alice_bob', 'alice', 'bob', 14)]);

      battery.status = const BatteryStatus(level: 13, charging: false);
      now = now.add(const Duration(seconds: 11));
      await lowService.onNewLocation(
        LiveLocationPoint(
          latitude: firstPoint.latitude + 0.0004,
          longitude: firstPoint.longitude,
          accuracy: 6,
          timestamp: now,
        ),
      );
      expect(notices, hasLength(1));

      battery.status = const BatteryStatus(level: 13, charging: true);
      now = now.add(const Duration(seconds: 11));
      await lowService.onNewLocation(
        LiveLocationPoint(
          latitude: firstPoint.latitude + 0.0006,
          longitude: firstPoint.longitude,
          accuracy: 6,
          timestamp: now,
        ),
      );
      battery.status = const BatteryStatus(level: 12, charging: false);
      now = now.add(const Duration(seconds: 11));
      await lowService.onNewLocation(
        LiveLocationPoint(
          latitude: firstPoint.latitude + 0.0008,
          longitude: firstPoint.longitude,
          accuracy: 6,
          timestamp: now,
        ),
      );
      expect(notices, hasLength(2));
      expect(repository.updated.last.batteryLevel, 12);

      await lowService.stopSharing();
    });
  });
}

class _HangingBattery implements BatteryReader {
  bool hang = false;

  @override
  Future<BatteryStatus?> read() {
    if (hang) return Completer<BatteryStatus?>().future;
    return Future.value(const BatteryStatus(level: 80, charging: true));
  }
}

class _MemoryKv implements StorageStringKv {
  final _values = <String, String>{};

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> delete(String key) async => _values.remove(key);
}

class _FakeBattery implements BatteryReader {
  _FakeBattery(this.status);

  BatteryStatus? status;

  @override
  Future<BatteryStatus?> read() async => status;
}

class _CapturingLocationSource implements LocationSource {
  LocationUpdateConfig? config;

  @override
  Future<bool> isServiceEnabled() async => true;

  @override
  Future<GeoFix?> lastKnown() async => null;

  @override
  Future<GeoFix> current({Duration? timeLimit}) => throw UnimplementedError();

  @override
  Stream<GeoFix> updates([
    LocationUpdateConfig config = const LocationUpdateConfig(),
  ]) {
    this.config = config;
    return const Stream<GeoFix>.empty();
  }
}

class _FakeLiveLocationRepository implements LiveLocationRepository {
  final refreshRequests =
      StreamController<LiveLocationRefreshRequest?>.broadcast();
  final acknowledgedRefreshRequests = <(String, String, String)>[];
  final started =
      <
        ({
          String sessionId,
          String threadId,
          String userId,
          LiveLocationPoint initialPoint,
        })
      >[];
  final updated = <LiveLocationPoint>[];
  final stopped = <(String, String, String)>[];

  @override
  Future<void> startSession({
    required String sessionId,
    required String threadId,
    required String userId,
    required Duration duration,
    required LiveLocationPoint initialPoint,
  }) async {
    started.add((
      sessionId: sessionId,
      threadId: threadId,
      userId: userId,
      initialPoint: initialPoint,
    ));
  }

  @override
  Future<void> updateLocation({
    required String sessionId,
    required String threadId,
    required String userId,
    required LiveLocationPoint point,
  }) async {
    updated.add(point);
  }

  @override
  Future<void> stopSession({
    required String sessionId,
    required String threadId,
    required String userId,
  }) async {
    stopped.add((sessionId, threadId, userId));
  }

  @override
  Stream<LiveLocationSession?> watchUserSession({
    required String sessionId,
    required String threadId,
    required String userId,
  }) => const Stream.empty();

  @override
  Stream<List<LiveLocationSession>> watchThreadSessions({
    required String threadId,
  }) => Stream.value(const []);

  @override
  Future<void> requestRefresh({
    required String sessionId,
    required String threadId,
    required String requesterUid,
  }) async {}

  @override
  Stream<LiveLocationRefreshRequest?> watchRefreshRequest({
    required String sessionId,
    required String threadId,
  }) => refreshRequests.stream;

  @override
  Future<void> acknowledgeRefreshRequest({
    required String sessionId,
    required String threadId,
    required String requestToken,
  }) async {
    acknowledgedRefreshRequests.add((requestToken, threadId, sessionId));
  }

  @override
  void dispose() {
    unawaited(refreshRequests.close());
  }
}
