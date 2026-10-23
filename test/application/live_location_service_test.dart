import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/services/live_location_service.dart';
import 'package:photo_vault/features/chat/domain/entities/live_location.dart';
import 'package:photo_vault/features/chat/domain/repositories/live_location_repository.dart';

void main() {
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
    positions = StreamController<LiveLocationPoint>();
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
    final session = LiveLocationSession(
      sessionId: 'session_1',
      threadId: 'alice_bob',
      userId: 'alice',
      isActive: false,
      startedAt: DateTime.utc(2026, 10, 21, 11),
      expiresAt: DateTime.utc(2026, 10, 21, 11, 15),
      lastUpdatedAt: DateTime.utc(2026, 10, 21, 11, 10),
      currentPoint: firstPoint,
    );

    expect(session.isActive, isFalse);
    expect(session.isLive, isFalse);
    expect(session.currentPoint, equals(firstPoint));
  });
}

class _FakeLiveLocationRepository implements LiveLocationRepository {
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
  void dispose() {}
}
