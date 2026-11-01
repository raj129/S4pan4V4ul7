import 'dart:math' as math;

import '../geo_fix.dart';

/// Traffic level on a stretch of road, as reported by the Google Routes API.
enum TrafficBand {
  normal('Normal traffic', 1.0),
  slow('Slow traffic', 0.45),
  jam('Traffic jam', 0.15),
  unknown('No traffic data', 1.0);

  const TrafficBand(this.label, this.speedFactor);

  final String label;

  /// Multiplier applied to the profile's base speed.
  final double speedFactor;

  static TrafficBand fromApi(String? value) => switch (value) {
    'NORMAL' => TrafficBand.normal,
    'SLOW' => TrafficBand.slow,
    'TRAFFIC_JAM' => TrafficBand.jam,
    _ => TrafficBand.unknown,
  };
}

/// How the simulated traveller moves.
enum TravelProfile {
  walk('Walk', 'WALK', 'walking', 5),
  cycle('Cycle', 'BICYCLE', 'bicycling', 15),
  drive('Drive', 'DRIVE', 'driving', 50);

  const TravelProfile(
    this.label,
    this.routesTravelMode,
    this.directionsMode,
    this.defaultSpeedKmh,
  );

  final String label;
  final String routesTravelMode;
  final String directionsMode;
  final double defaultSpeedKmh;

  /// Only driving routes carry traffic speed readings.
  bool get supportsTraffic => this == TravelProfile.drive;

  static TravelProfile fromName(String? name) => TravelProfile.values
      .firstWhere((p) => p.name == name, orElse: () => TravelProfile.drive);
}

/// Where a simulated route came from.
enum SimRouteSource {
  routesWithTraffic('Google Routes (live traffic)'),
  routes('Google Routes'),
  directions('Google Directions'),
  straightLine('Straight line (no API key or route)');

  const SimRouteSource(this.label);
  final String label;
}

/// A polyline with a traffic band per segment, ready to simulate.
class SimRoute {
  SimRoute({
    required List<GeoCoord> points,
    List<TrafficBand>? segmentBands,
    required this.source,
    this.apiDurationSeconds,
    this.warning,
  }) : assert(points.length >= 2, 'A route needs at least two points'),
       points = List.unmodifiable(points),
       segmentBands = List.unmodifiable(
         segmentBands ?? List.filled(points.length - 1, TrafficBand.unknown),
       ),
       _cumulative = _cumulativeDistances(points) {
    assert(this.segmentBands.length == points.length - 1);
  }

  /// Straight line from [a] to [b], split so the simulator emits smooth fixes.
  factory SimRoute.straightLine(GeoCoord a, GeoCoord b, {String? warning}) {
    final distance = a.distanceTo(b);
    final steps = math.max(1, (distance / 50).ceil()).clamp(1, 500);
    return SimRoute(
      points: [for (var i = 0; i <= steps; i++) a.lerp(b, i / steps)],
      source: SimRouteSource.straightLine,
      warning: warning,
    );
  }

  final List<GeoCoord> points;
  final List<TrafficBand> segmentBands;
  final SimRouteSource source;
  final int? apiDurationSeconds;

  /// Why a richer route source could not be used, if any.
  final String? warning;
  final List<double> _cumulative;

  double get totalMeters => _cumulative.last;
  GeoCoord get origin => points.first;
  GeoCoord get destination => points.last;
  bool get hasTraffic => segmentBands.any((b) => b != TrafficBand.unknown);

  static List<double> _cumulativeDistances(List<GeoCoord> points) {
    final out = List<double>.filled(points.length, 0);
    for (var i = 1; i < points.length; i++) {
      out[i] = out[i - 1] + points[i - 1].distanceTo(points[i]);
    }
    return out;
  }

  /// Index of the segment containing [distance] metres along the route.
  int segmentAt(double distance) {
    if (distance <= 0) return 0;
    if (distance >= totalMeters) return points.length - 2;
    var lo = 0;
    var hi = points.length - 1;
    while (hi - lo > 1) {
      final mid = (lo + hi) >> 1;
      if (_cumulative[mid] <= distance) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  GeoCoord positionAt(double distance) {
    final d = distance.clamp(0.0, totalMeters);
    final i = segmentAt(d);
    final segLen = _cumulative[i + 1] - _cumulative[i];
    if (segLen <= 0) return points[i];
    return points[i].lerp(points[i + 1], (d - _cumulative[i]) / segLen);
  }

  TrafficBand bandAt(double distance) => segmentBands[segmentAt(distance)];

  double bearingAt(double distance) {
    final i = segmentAt(distance);
    return points[i].bearingTo(points[i + 1]);
  }

  /// Largest heading change, in degrees, within [lookahead] metres.
  double turnAngleAhead(double distance, double lookahead) {
    final start = segmentAt(distance);
    final startBearing = bearingAt(distance);
    var maxTurn = 0.0;
    for (var i = start + 1; i < points.length - 1; i++) {
      if (_cumulative[i] - distance > lookahead) break;
      if (points[i].distanceTo(points[i + 1]) < 1) continue;
      final b = points[i].bearingTo(points[i + 1]);
      var diff = (b - startBearing).abs() % 360;
      if (diff > 180) diff = 360 - diff;
      maxTurn = math.max(maxTurn, diff);
    }
    return maxTurn;
  }

  /// The part of the route from [distance] to the end, keeping traffic bands.
  SimRoute remainingFrom(double distance) {
    final i = segmentAt(distance);
    final start = positionAt(distance);
    return SimRoute(
      points: [start, ...points.sublist(i + 1)],
      segmentBands: segmentBands.sublist(i),
      source: source,
    );
  }

  /// Share of the route length in each traffic band.
  Map<TrafficBand, double> bandShares() {
    final totals = <TrafficBand, double>{};
    for (var i = 0; i < segmentBands.length; i++) {
      final len = _cumulative[i + 1] - _cumulative[i];
      totals.update(segmentBands[i], (v) => v + len, ifAbsent: () => len);
    }
    if (totalMeters <= 0) return totals;
    return totals.map((k, v) => MapEntry(k, v / totalMeters));
  }
}
