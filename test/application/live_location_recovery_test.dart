import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/location/app_location.dart';
import 'package:photo_vault/core/location/geo_fix.dart';
import 'package:photo_vault/core/location/location_source.dart';
import 'package:photo_vault/features/chat/application/services/live_location_health.dart';
import 'package:photo_vault/features/chat/application/services/live_location_service.dart';
import 'package:photo_vault/features/chat/domain/entities/live_location.dart';
import 'package:photo_vault/features/chat/domain/repositories/live_location_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_string_kv.dart';

class _Repository implements LiveLocationRepository {
  final updates = <LiveLocationPoint>[];
  // ignore: close_sinks - closed by the harness teardown.
  final requests = StreamController<LiveLocationRefreshRequest?>.broadcast();
  final acknowledgements = <String>[];
  Future<void> Function()? write;
  bool failStop = false;

  @override
  Future<void> startSession({
    required String sessionId,
    required String threadId,
    required String userId,
    required Duration duration,
    required LiveLocationPoint initialPoint,
  }) async {}

  @override
  Future<void> updateLocation({
    required String sessionId,
    required String threadId,
    required String userId,
    required LiveLocationPoint point,
  }) async {
    await write?.call();
    updates.add(point);
  }

  @override
  Future<void> stopSession({
    required String sessionId,
    required String threadId,
    required String userId,
  }) async {
    if (failStop) throw StateError('offline');
  }

  @override
  Stream<LiveLocationRefreshRequest?> watchRefreshRequest({
    required String sessionId,
    required String threadId,
  }) => requests.stream;

  @override
  Future<void> acknowledgeRefreshRequest({
    required String sessionId,
    required String threadId,
    required String requestToken,
  }) async => acknowledgements.add(requestToken);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Store implements StorageStringKv {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) throw StateError('storage unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) throw StateError('storage unavailable');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async => values.remove(key);
}

class _RealSource extends LocationSource {
  final streams = <StreamController<GeoFix>>[];
  @override
  Stream<GeoFix> updates([
    LocationUpdateConfig config = const LocationUpdateConfig(),
  ]) {
    final controller = StreamController<GeoFix>();
    streams.add(controller);
    return controller.stream;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Harness {
  _Harness(this.tester, {LiveLocationUpdates? source}) {
    origin = tester.binding.clock.now();
    service = LiveLocationService(
      repository: repository,
      clock: () => tester.binding.clock.now(),
      elapsed: () => tester.binding.clock.now().difference(origin),
      store: store,
      locationUpdates:
          source ??
          () {
            final stream = StreamController<LiveLocationPoint>.broadcast();
            streams.add(stream);
            return stream.stream;
          },
    );
    addTearDown(() {
      service.dispose();
      for (final stream in streams) {
        unawaited(stream.close());
      }
      unawaited(repository.requests.close());
    });
  }
  final WidgetTester tester;
  final repository = _Repository();
  final store = _Store();
  final streams = <StreamController<LiveLocationPoint>>[];
  late final DateTime origin;
  late final LiveLocationService service;

  LiveLocationPoint point({DateTime? timestamp, double latitude = 1}) =>
      LiveLocationPoint(
        latitude: latitude,
        longitude: 2,
        accuracy: 5,
        timestamp: timestamp ?? tester.binding.clock.now(),
      );

  Future<void> start() => service.startSharing(
    threadId: 'alice_bob',
    userId: 'alice',
    duration: const Duration(hours: 1),
    initialPoint: point(),
  );
}

void main() {
  testWidgets('silent open stream recovers at 60 seconds without fake writes', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    await tester.pump(const Duration(seconds: 59));
    expect(h.streams, hasLength(1));
    await tester.pump(const Duration(seconds: 1));
    expect(h.streams, hasLength(2));
    expect(h.repository.updates, isEmpty);
    expect(
      h.service.health.events.map((e) => e['event']),
      contains('source_silent'),
    );
    h.streams.last.add(h.point());
    await tester.pump();
    expect(h.repository.updates, hasLength(1));
    expect(h.service.healthSnapshot['retryAttempt'], 0);
    await h.service.stopSharing();
    await tester.pump(const Duration(minutes: 5));
    expect(h.streams, hasLength(2));
  });

  testWidgets(
    'healthy stationary callbacks preserve heartbeat and do not restart',
    (tester) async {
      final h = _Harness(tester);
      await h.start();
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(seconds: 10));
        h.streams.last.add(h.point());
        await tester.pump();
      }
      expect(h.streams, hasLength(1));
      expect(h.repository.updates, hasLength(2));
      await h.service.stopSharing();
    },
  );

  testWidgets('repeated cached fixes do not mask a silent GPS source', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    for (var i = 0; i < 7; i++) {
      await tester.pump(const Duration(seconds: 10));
      h.streams.last.add(
        h.point(timestamp: h.origin.subtract(const Duration(minutes: 5))),
      );
      await tester.pump();
    }
    expect(h.streams, hasLength(2));
    expect(h.repository.updates, isEmpty);
    expect(h.service.healthSnapshot['callbackAgeMs'], 0);
    expect(h.service.healthSnapshot['freshFixAgeMs'], isNull);
    await h.service.stopSharing();
  });

  testWidgets(
    'silent restart attempts back off rather than restarting every health tick',
    (tester) async {
      final h = _Harness(tester);
      await h.start();
      await tester.pump(const Duration(seconds: 60));
      expect(h.streams, hasLength(2));
      await tester.pump(const Duration(seconds: 60));
      expect(h.streams, hasLength(3));
      await tester.pump(const Duration(seconds: 60));
      expect(h.streams, hasLength(3));
      await tester.pump(const Duration(seconds: 60));
      expect(h.streams, hasLength(4));
      await h.service.stopSharing();
    },
  );

  testWidgets('fresh callbacks reset silent-recovery backoff', (tester) async {
    final h = _Harness(tester);
    await h.start();
    await tester.pump(const Duration(seconds: 60));
    await tester.pump(const Duration(seconds: 60));
    expect(h.streams, hasLength(3));
    await tester.pump(const Duration(seconds: 10));
    h.streams.last.add(h.point());
    await tester.pump();
    await tester.pump(const Duration(seconds: 65));
    expect(h.streams, hasLength(4));
    await h.service.stopSharing();
  });

  testWidgets('notification changes do not wait for a GPS fix', (tester) async {
    final h = _Harness(tester);
    await h.start();
    await h.service.refreshNotification();
    expect(h.streams, hasLength(2));
    expect(h.repository.updates, isEmpty);
    expect(
      h.service.health.events.map((event) => event['event']),
      isNot(contains('refresh_published')),
    );
    await h.service.stopSharing();
  });

  testWidgets('production wrapper forwards source completion into retry', (
    tester,
  ) async {
    final previous = AppLocation.instance;
    final real = _RealSource();
    final location = AppLocation(real: real);
    AppLocation.instance = location;
    final h = _Harness(
      tester,
      source: () => location.updates().map(
        (fix) => LiveLocationPoint(
          latitude: fix.latitude,
          longitude: fix.longitude,
          accuracy: fix.accuracy,
          timestamp: fix.timestamp,
        ),
      ),
    );
    addTearDown(() {
      AppLocation.instance = previous;
      location.mock.dispose();
    });
    await h.start();
    await tester.pump();
    expect(real.streams, hasLength(1));
    unawaited(real.streams.first.close());
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(real.streams, hasLength(2));
    await h.service.stopSharing();
  });

  testWidgets(
    'refresh and resume coalesce and refresh waits for a new publication',
    (tester) async {
      final h = _Harness(tester);
      await h.start();
      await tester.pump(const Duration(seconds: 11));
      var completed = false;
      final refreshed = h.service.refreshSharing().then(
        (_) => completed = true,
      );
      h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
      final second = h.service.refreshSharing();
      await tester.pump();
      expect(h.streams, hasLength(2));
      expect(completed, isFalse);
      h.streams.last.add(h.point(timestamp: h.origin));
      await tester.pump();
      expect(completed, isFalse);
      await tester.pump(const Duration(seconds: 11));
      h.streams.last.add(h.point(latitude: 1.001));
      await tester.pump();
      await refreshed;
      await second;
      expect(completed, isTrue);
      await h.service.stopSharing();
    },
  );

  testWidgets(
    'remote refresh is not acknowledged on setup alone and retries after failure',
    (tester) async {
      final h = _Harness(tester);
      await h.start();
      h.repository.write = () async => throw StateError('offline');
      h.repository.requests.add(
        LiveLocationRefreshRequest(
          requestToken: 'request',
          requestedBy: 'bob',
          requestedAt: h.origin,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      h.streams.last.add(h.point(latitude: 1.001));
      await tester.pump();
      expect(h.repository.acknowledgements, isEmpty);
      await tester.pump(const Duration(seconds: 80));
      expect(h.repository.acknowledgements, isEmpty);
      h.repository.write = null;
      await tester.pump(const Duration(seconds: 30));
      h.streams.last.add(h.point(latitude: 1.002));
      await tester.pump();
      expect(h.repository.acknowledgements, ['request']);
      await h.service.stopSharing();
    },
  );

  testWidgets('stop failure leaves local sharing stopped and cannot resume', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.repository.failStop = true;
    await expectLater(h.service.stopSharing(), throwsStateError);
    expect(h.service.isSharing, isFalse);
    expect(h.store.values[LiveLocationService.storageKey], isNull);
    h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump(const Duration(minutes: 2));
    expect(h.streams, hasLength(1));
    await expectLater(h.service.refreshSharing(), throwsStateError);
  });

  testWidgets('late old publication cannot update a replacement session', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    final oldWrite = Completer<void>();
    h.repository.write = () => oldWrite.future;
    await tester.pump(const Duration(seconds: 11));
    final old = h.service.onNewLocation(h.point(latitude: 1.001));
    await tester.pump();
    await h.service.stopSharing();
    h.repository.write = null;
    await h.start();
    final published = h.service.healthSnapshot['lastPublishedAt'];
    await tester.pump(const Duration(seconds: 11));
    oldWrite.complete();
    await old;
    expect(h.service.healthSnapshot['lastPublishedAt'], published);
    await h.service.onNewLocation(h.point(latitude: 1.002));
    expect(h.service.healthSnapshot['writeInFlight'], isFalse);
    await h.service.stopSharing();
  });

  testWidgets(
    'hanging source setup times out and late completion cannot attach',
    (tester) async {
      final opening = Completer<Stream<LiveLocationPoint>>();
      var calls = 0;
      final h = _Harness(
        tester,
        source: () {
          calls++;
          return opening.future;
        },
      );
      var started = false;
      final start = h.start().then((_) => started = true);
      await tester.pump(const Duration(seconds: 10));
      await start;
      expect(started, isTrue);
      expect(calls, 1);
      await h.service.stopSharing();
      var listened = false;
      opening.complete(
        Stream<LiveLocationPoint>.multi((controller) {
          listened = true;
          controller.close();
        }),
      );
      await tester.pump(const Duration(minutes: 2));
      expect(listened, isFalse);
      expect(calls, 1);
    },
  );

  testWidgets(
    'old callbacks cannot refresh timestamps during a silent GPS stall',
    (tester) async {
      final h = _Harness(tester);
      await h.start();
      await tester.pump(const Duration(seconds: 61));
      h.streams.last.add(h.point(timestamp: h.origin, latitude: 1.001));
      await tester.pump();
      expect(h.repository.updates, isEmpty);
      await h.service.stopSharing();
    },
  );

  testWidgets('a hanging upload times out without restarting healthy GPS', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    final write = Completer<void>();
    h.repository.write = () => write.future;
    await tester.pump(const Duration(seconds: 11));
    h.streams.last.add(h.point(latitude: 1.001));
    await tester.pump();
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 10));
      h.streams.last.add(h.point(latitude: 1.002));
      await tester.pump();
    }
    expect(h.streams, hasLength(1));
    expect(
      h.service.health.events.map((e) => e['event']),
      contains('publish_failed'),
    );
    h.repository.write = null;
    write.complete();
    await tester.pump(const Duration(seconds: 10));
    h.streams.last.add(h.point(latitude: 1.003));
    await tester.pump();
    expect(h.service.healthSnapshot['writeInFlight'], isFalse);
    await h.service.stopSharing();
  });

  testWidgets('hanging cancellation is bounded and retry continues', (
    tester,
  ) async {
    final cancellation = Completer<void>();
    final first = StreamController<LiveLocationPoint>(
      onCancel: () => cancellation.future,
    );
    final later = StreamController<LiveLocationPoint>.broadcast();
    var calls = 0;
    final h = _Harness(
      tester,
      source: () => ++calls == 1 ? first.stream : later.stream,
    );
    await h.start();
    final refreshed = h.service.refreshSharing();
    final failed = expectLater(refreshed, throwsA(isA<TimeoutException>()));
    await tester.pump();
    await tester.pump(const Duration(seconds: 10));
    await failed;
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    cancellation.complete();
    await tester.pump();
    await h.service.stopSharing();
    unawaited(first.close());
    unawaited(later.close());
  });

  testWidgets('expiry and disposal cancel pending recovery and refresh', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    final refreshed = h.service.refreshSharing();
    final cancelled = expectLater(refreshed, throwsStateError);
    await tester.pump();
    h.service.dispose();
    await cancelled;
    final count = h.streams.length;
    await tester.pump(const Duration(hours: 2));
    expect(h.streams, hasLength(count));
  });

  testWidgets('watchdog cannot recover an expired session', (tester) async {
    final h = _Harness(tester);
    await h.start();
    await tester.pump(const Duration(hours: 1));
    await tester.pump();
    expect(h.service.isSharing, isFalse);
    final count = h.streams.length;
    await tester.pump(const Duration(minutes: 5));
    expect(h.streams, hasLength(count));
  });

  testWidgets('diagnostic storage failure does not stop healthy publishing', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    h.store.fail = true;
    h.service.health.record('diagnostic_failure');
    await tester.pump(const Duration(seconds: 11));
    h.streams.last.add(h.point(latitude: 1.001));
    await tester.pump();
    expect(h.repository.updates, hasLength(1));
    h.store.fail = false;
    await h.service.stopSharing();
  });

  test(
    'diagnostics are capped, persisted, and contain no exception payload',
    () async {
      final store = _Store();
      final health = LiveLocationHealth(store: store);
      await health.settled;
      for (var i = 0; i < 70; i++) {
        health.record(
          'retry',
          attempt: i,
          error: StateError('secret coordinates'),
        );
      }
      await health.settled;
      expect(health.events, hasLength(LiveLocationHealth.capacity));
      final raw = store.values[LiveLocationHealth.storageKey]!;
      expect(raw, isNot(contains('secret coordinates')));
      expect(jsonDecode(raw), hasLength(50));
      final restored = LiveLocationHealth(store: store);
      await restored.settled;
      expect(restored.events, health.events);
      store.fail = true;
      restored.record('storage_test');
      await restored.settled;
      expect(restored.events.last['event'], 'storage_test');
    },
  );

  testWidgets('resume does not restart a healthy active location stream', (
    tester,
  ) async {
    final h = _Harness(tester);
    await h.start();
    await tester.pump(const Duration(seconds: 15));
    h.streams.last.add(h.point(latitude: 1.001));
    await tester.pump();
    expect(h.streams, hasLength(1));

    h.service.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.streams, hasLength(1));
    await h.service.stopSharing();
  });
}
