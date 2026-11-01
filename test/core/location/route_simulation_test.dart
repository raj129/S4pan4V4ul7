import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_vault/core/location/geo_fix.dart';
import 'package:photo_vault/core/location/mock/mock_location_preferences.dart';
import 'package:photo_vault/core/location/mock/polyline_codec.dart';
import 'package:photo_vault/core/location/mock/route_simulator.dart';
import 'package:photo_vault/core/location/mock/sim_route.dart';
import 'package:photo_vault/core/location/mock/traffic_route_service.dart';

const _a = GeoCoord(12.9716, 77.5946);
const _b = GeoCoord(12.9816, 77.5946); // ~1.1 km north

SimRoute _route(TrafficBand band) {
  final line = SimRoute.straightLine(_a, _b);
  return SimRoute(
    points: line.points,
    segmentBands: List.filled(line.points.length - 1, band),
    source: SimRouteSource.routesWithTraffic,
  );
}

double _runFor(RouteSimulator sim, int seconds) {
  final t0 = DateTime(2024);
  for (var i = 0; i < seconds; i++) {
    sim.step(const Duration(seconds: 1), t0.add(Duration(seconds: i)));
  }
  return sim.distanceAlong;
}

const _polyline = r'_p~iF~ps|U_ulLnnqC_mqNvxq`@';

void main() {
  test('PolylineCodec decodes Google reference polyline', () {
    final pts = PolylineCodec.decode(_polyline);
    expect(pts, hasLength(3));
    expect(pts[0].latitude, closeTo(38.5, 1e-5));
    expect(pts[0].longitude, closeTo(-120.2, 1e-5));
    expect(pts[2].latitude, closeTo(43.252, 1e-5));
    expect(pts[2].longitude, closeTo(-126.453, 1e-5));
  });

  group('RouteSimulator', () {
    const config = SimulationConfig(baseSpeedKmh: 36, trafficRefresh: null);

    test('traffic jams slow the traveller down', () {
      final free = RouteSimulator(
        route: _route(TrafficBand.normal),
        config: config,
        random: math.Random(1),
      );
      final jam = RouteSimulator(
        route: _route(TrafficBand.jam),
        config: config,
        random: math.Random(1),
      );
      final freeDist = _runFor(free, 40);
      final jamDist = _runFor(jam, 40);
      expect(jamDist, lessThan(freeDist * 0.4));
      expect(
        jam.roadSpeedMps,
        lessThan(10 * TrafficBand.jam.speedFactor * 1.1),
      );
    });

    test('ignoring traffic keeps cruise speed', () {
      final sim = RouteSimulator(
        route: _route(TrafficBand.jam),
        config: config.copyWith(followTraffic: false),
        random: math.Random(1),
      );
      _runFor(sim, 40);
      expect(sim.roadSpeedMps, greaterThan(9));
    });

    test('arrives, stops and reports finished', () {
      final sim = RouteSimulator(
        route: _route(TrafficBand.normal),
        config: config.copyWith(multiplier: 10),
        random: math.Random(2),
      );
      _runFor(sim, 60);
      final snap = sim.snapshot(DateTime(2024));
      expect(snap.status, SimStatus.finished);
      expect(snap.progress, 1);
      expect(snap.fix.coord.distanceTo(_b), lessThan(1));
      expect(snap.fix.isMock, isTrue);
      expect(snap.remainingSeconds, 0);
    });

    test('loops back to the start when loop is on', () {
      final sim = RouteSimulator(
        route: _route(TrafficBand.normal),
        config: config.copyWith(multiplier: 10, loop: true),
        random: math.Random(3),
      );
      _runFor(sim, 60);
      expect(sim.status, SimStatus.running);
      expect(sim.distanceAlong, lessThan(sim.route.totalMeters));
    });

    test('pause holds position and resume continues', () {
      final sim = RouteSimulator(
        route: _route(TrafficBand.normal),
        config: config,
        random: math.Random(4),
      );
      _runFor(sim, 10);
      sim.pause();
      final held = sim.distanceAlong;
      _runFor(sim, 10);
      expect(sim.distanceAlong, held);
      expect(sim.snapshot(DateTime(2024)).fix.speed, 0);
      sim.resume();
      _runFor(sim, 5);
      expect(sim.distanceAlong, greaterThan(held));
    });

    test('ETA reflects traffic', () {
      final t = DateTime(2024);
      final free = RouteSimulator(
        route: _route(TrafficBand.normal),
        config: config,
      ).snapshot(t);
      final jam = RouteSimulator(
        route: _route(TrafficBand.jam),
        config: config,
      ).snapshot(t);
      expect(jam.remainingSeconds, greaterThan(free.remainingSeconds * 5));
    });

    test('bandShares sums to 1', () {
      final line = SimRoute.straightLine(_a, _b);
      final n = line.points.length - 1;
      final route = SimRoute(
        points: line.points,
        segmentBands: [
          for (var i = 0; i < n; i++)
            i < n ~/ 2 ? TrafficBand.normal : TrafficBand.jam,
        ],
        source: SimRouteSource.routesWithTraffic,
      );
      final total = route.bandShares().values.fold<double>(0, (a, b) => a + b);
      expect(total, closeTo(1, 1e-9));
      expect(route.hasTraffic, isTrue);
    });
  });

  group('TrafficRouteService', () {
    final routesBody = jsonEncode({
      'routes': [
        {
          'distanceMeters': 1000,
          'duration': '321s',
          'polyline': {'encodedPolyline': _polyline},
          'travelAdvisory': {
            'speedReadingIntervals': [
              {'endPolylinePointIndex': 1, 'speed': 'TRAFFIC_JAM'},
              {
                'startPolylinePointIndex': 1,
                'endPolylinePointIndex': 2,
                'speed': 'SLOW',
              },
            ],
          },
        },
      ],
    });

    test('parses traffic bands and duration', () {
      final route = TrafficRouteService.parseRoutesResponse(routesBody);
      expect(route.points, hasLength(3));
      expect(route.segmentBands, [TrafficBand.jam, TrafficBand.slow]);
      expect(route.source, SimRouteSource.routesWithTraffic);
      expect(route.apiDurationSeconds, 321);
    });

    test('requests traffic-aware route from the Routes API', () async {
      late http.Request seen;
      final service = TrafficRouteService(
        apiKey: 'k',
        client: MockClient((req) async {
          seen = req;
          return http.Response(routesBody, 200);
        }),
      );
      final route = await service.fetch(origin: _a, destination: _b);
      expect(route.hasTraffic, isTrue);
      expect(seen.headers['X-Goog-Api-Key'], 'k');
      final body = jsonDecode(seen.body) as Map<String, dynamic>;
      expect(body['routingPreference'], 'TRAFFIC_AWARE_OPTIMAL');
      expect(body['extraComputations'], ['TRAFFIC_ON_POLYLINE']);
    });

    test('falls back to a straight line when Routes fails', () async {
      final failing = TrafficRouteService(
        apiKey: 'r',
        client: MockClient(
          (_) async => http.Response('{"error":{"message":"denied"}}', 403),
        ),
      );
      final route = await failing.fetch(origin: _a, destination: _b);
      expect(route.source, SimRouteSource.straightLine);
      expect(route.warning, contains('denied'));

      final offline = TrafficRouteService(
        apiKey: 'r',
        client: MockClient((_) async => http.Response('', 500)),
      );
      final line = await offline.fetch(origin: _a, destination: _b);
      expect(line.source, SimRouteSource.straightLine);
      expect(line.warning, isNotNull);
    });
  });

  group('MockLocationPreferences', () {
    test('round-trips through encode/decode', () {
      const prefs = MockLocationPreferences(
        fixedPoint: _a,
        routeOrigin: _a,
        routeDestination: _b,
        profile: TravelProfile.cycle,
        baseSpeedKmh: 22,
        multiplier: 5,
        loop: true,
        followTraffic: false,
        trafficRefreshMinutes: 0,
        systemWide: true,
      );
      final back = MockLocationPreferences.decode(prefs.encode());
      expect(back.fixedPoint, _a);
      expect(back.routeDestination, _b);
      expect(back.profile, TravelProfile.cycle);
      expect(back.baseSpeedKmh, 22);
      expect(back.multiplier, 5);
      expect(back.loop, isTrue);
      expect(back.followTraffic, isFalse);
      expect(back.systemWide, isTrue);
      expect(back.toSimulationConfig().trafficRefresh, isNull);
    });

    test('corrupt data falls back to defaults', () {
      final prefs = MockLocationPreferences.decode('{not json');
      expect(prefs.fixedPoint, isNull);
      expect(prefs.profile, TravelProfile.drive);
    });
  });
}
