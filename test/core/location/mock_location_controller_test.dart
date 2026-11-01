import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/location/app_location.dart';
import 'package:photo_vault/core/location/geo_fix.dart';
import 'package:photo_vault/core/location/location_source.dart';
import 'package:photo_vault/core/location/mock/mock_location_controller.dart';
import 'package:photo_vault/core/location/mock/route_simulator.dart';
import 'package:photo_vault/core/location/mock/sim_route.dart';
import 'package:photo_vault/core/location/mock/system_mock_bridge.dart';
import 'package:photo_vault/core/location/presentation/mock_location_banner.dart';

const _home = GeoCoord(12.9716, 77.5946);
const _office = GeoCoord(12.9816, 77.5946);

class _FakeReal implements LocationSource {
  // ignore: close_sinks - test fake lives for the whole test.
  final updatesController = StreamController<GeoFix>.broadcast();
  int streamListens = 0;

  static GeoFix fix(double lat) =>
      GeoFix(latitude: lat, longitude: 1, timestamp: DateTime.utc(2024));

  @override
  Future<bool> isServiceEnabled() async => false;

  @override
  Future<GeoFix?> lastKnown() async => fix(50);

  @override
  Future<GeoFix> current({Duration? timeLimit}) async => fix(50);

  @override
  Stream<GeoFix> updates([
    LocationUpdateConfig config = const LocationUpdateConfig(),
  ]) {
    streamListens++;
    return updatesController.stream;
  }
}

class _FakeBridge extends SystemMockBridge {
  SystemMockAvailability available = SystemMockAvailability.ready;
  final calls = <String>[];
  final pushed = <GeoFix>[];
  void Function()? stopHandler;

  @override
  set onStopRequested(void Function()? handler) => stopHandler = handler;

  @override
  Future<SystemMockAvailability> availability() async => available;

  @override
  Future<void> start({required String status}) async => calls.add('start');

  @override
  Future<void> push(GeoFix fix, {String? status}) async => pushed.add(fix);

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  late _FakeBridge bridge;
  late MockLocationController mock;
  late _FakeReal real;
  late AppLocation location;
  var now = DateTime.utc(2024);

  setUp(() {
    now = DateTime.utc(2024);
    bridge = _FakeBridge();
    mock = MockLocationController(systemBridge: bridge, clock: () => now);
    real = _FakeReal();
    location = AppLocation(real: real, mock: mock);
  });

  tearDown(() => mock.dispose());

  test('one-shot reads come from the mock while it is on', () async {
    expect((await location.current()).latitude, 50);
    expect(await location.isServiceEnabled(), isFalse);

    mock.enableFixed(_home, accuracy: 8);
    final fix = await location.current();
    expect(fix.coord, _home);
    expect(fix.isMock, isTrue);
    expect(fix.accuracy, 8);
    expect(await location.isServiceEnabled(), isTrue);
    expect(mock.statusLabel, contains('Fixed point'));

    await mock.useRealGps();
    expect(location.isMocking, isFalse);
    expect((await location.lastKnown())!.latitude, 50);
  });

  test('live stream switches between real and mock instantly', () async {
    final received = <GeoFix>[];
    final sub = location
        .updates(const LocationUpdateConfig(interval: Duration.zero))
        .listen(received.add);
    await pumpEventQueue();

    real.updatesController.add(_FakeReal.fix(51));
    await pumpEventQueue();
    expect(received.single.latitude, 51);

    mock.enableFixed(_home);
    await pumpEventQueue();
    expect(received.last.coord, _home);
    expect(received.last.isMock, isTrue);

    // Real GPS output is ignored while mocking.
    real.updatesController.add(_FakeReal.fix(52));
    await pumpEventQueue();
    expect(received.last.coord, _home);

    await mock.useRealGps();
    await pumpEventQueue();
    real.updatesController.add(_FakeReal.fix(53));
    await pumpEventQueue();
    expect(received.last.latitude, 53);
    expect(real.streamListens, 2);
    await sub.cancel();
  });

  test('route simulation ticks and moves along the route', () async {
    final controller = MockLocationController(
      systemBridge: _FakeBridge(),
      tick: const Duration(milliseconds: 20),
    );
    final fixes = <GeoFix>[];
    final sub = controller.fixes.listen(fixes.add);
    // 20 ms ticks at 20x = 0.4 simulated seconds per tick.
    controller.startRoute(
      SimRoute.straightLine(_home, _office),
      const SimulationConfig(
        baseSpeedKmh: 36,
        multiplier: 20,
        trafficRefresh: null,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(controller.mode, MockMode.route);
    expect(controller.snapshot!.distanceAlong, greaterThan(20));
    expect(fixes.length, greaterThanOrEqualTo(10));
    expect(controller.statusLabel, startsWith('Route'));

    controller.pauseRoute();
    final held = controller.snapshot!.distanceAlong;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(controller.snapshot!.distanceAlong, held);
    expect(controller.statusLabel, contains('paused'));
    await sub.cancel();
    controller.dispose();
  });

  test('traffic refresh swaps in the remaining route', () async {
    var calls = 0;
    mock.startRoute(
      SimRoute.straightLine(_home, _office),
      const SimulationConfig(baseSpeedKmh: 36),
      refresher: (from) async {
        calls++;
        final line = SimRoute.straightLine(from, _office);
        return SimRoute(
          points: line.points,
          segmentBands: List.filled(line.points.length - 1, TrafficBand.jam),
          source: SimRouteSource.routesWithTraffic,
        );
      },
    );
    await mock.refreshTrafficNow();
    expect(calls, 1);
    expect(mock.simulator!.route.hasTraffic, isTrue);
    expect(mock.trafficRefreshError, isNull);
  });

  test('system-wide mirrors fixes and stops with real GPS', () async {
    await mock.setSystemWide(true);
    expect(bridge.calls, isEmpty, reason: 'nothing to mirror yet');

    mock.enableFixed(_home);
    await pumpEventQueue();
    expect(mock.systemWideRunning, isTrue);
    expect(bridge.calls, ['start']);
    expect(bridge.pushed, isNotEmpty);

    await mock.useRealGps();
    expect(bridge.calls, ['start', 'stop']);
    expect(mock.systemWideRunning, isFalse);
  });

  test('system-wide reports when the app is not the mock app', () async {
    bridge.available = SystemMockAvailability.notSelected;
    mock.enableFixed(_home);
    await mock.setSystemWide(true);
    expect(mock.systemWide, isFalse);
    expect(mock.systemWideError, contains('Select mock location app'));
  });

  test('notification Stop action returns to real GPS', () async {
    mock.enableFixed(_home);
    await mock.setSystemWide(true);
    bridge.stopHandler!();
    await pumpEventQueue();
    expect(mock.isActive, isFalse);
  });

  testWidgets('banner reminds the user and switches back to real GPS', (
    tester,
  ) async {
    final visible = ValueNotifier(true);
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MockLocationBanner(
          controller: mock,
          visibilityListenable: visible,
          isVisible: () => visible.value,
          onOpen: () => opened = true,
          child: child!,
        ),
        home: const Scaffold(body: Text('content')),
      ),
    );
    expect(find.byKey(const Key('mock-location-banner')), findsNothing);

    mock.enableFixed(_home);
    await tester.pump();
    expect(find.byKey(const Key('mock-location-banner')), findsOneWidget);
    expect(find.textContaining('Mock location'), findsOneWidget);
    expect(find.text('content'), findsOneWidget);

    visible.value = false;
    await tester.pump();
    expect(find.byKey(const Key('mock-location-banner')), findsNothing);
    visible.value = true;
    await tester.pump();

    await tester.tap(find.text('Open'));
    expect(opened, isTrue);

    await tester.tap(find.byKey(const Key('mock-location-banner-use-real')));
    await tester.pump();
    expect(mock.isActive, isFalse);
    expect(find.byKey(const Key('mock-location-banner')), findsNothing);

    // Stop the periodic tick before the test ends.
    await mock.useRealGps();
  });
}
