import 'dart:math' as math;

import '../geo_fix.dart';
import 'sim_route.dart';

enum SimStatus { running, paused, finished }

class SimulationConfig {
  const SimulationConfig({
    this.profile = TravelProfile.drive,
    double? baseSpeedKmh,
    this.multiplier = 1,
    this.loop = false,
    this.followTraffic = true,
    this.trafficRefresh = const Duration(minutes: 5),
  }) : baseSpeedKmh = baseSpeedKmh ?? 0;

  final TravelProfile profile;
  final double baseSpeedKmh;

  /// Simulated seconds per real second.
  final double multiplier;
  final bool loop;

  /// Slow down on SLOW / TRAFFIC_JAM stretches.
  final bool followTraffic;

  /// How often to re-request traffic for the remaining route; null disables.
  final Duration? trafficRefresh;

  double get effectiveBaseKmh =>
      baseSpeedKmh > 0 ? baseSpeedKmh : profile.defaultSpeedKmh;
  double get baseSpeedMps => effectiveBaseKmh / 3.6;

  SimulationConfig copyWith({
    TravelProfile? profile,
    double? baseSpeedKmh,
    double? multiplier,
    bool? loop,
    bool? followTraffic,
    Duration? trafficRefresh,
    bool clearTrafficRefresh = false,
  }) => SimulationConfig(
    profile: profile ?? this.profile,
    baseSpeedKmh: baseSpeedKmh ?? this.baseSpeedKmh,
    multiplier: multiplier ?? this.multiplier,
    loop: loop ?? this.loop,
    followTraffic: followTraffic ?? this.followTraffic,
    trafficRefresh: clearTrafficRefresh
        ? null
        : trafficRefresh ?? this.trafficRefresh,
  );
}

/// What the simulator produced on one tick.
class SimSnapshot {
  const SimSnapshot({
    required this.fix,
    required this.status,
    required this.distanceAlong,
    required this.totalMeters,
    required this.band,
    required this.roadSpeedMps,
    required this.remainingSeconds,
  });

  final GeoFix fix;
  final SimStatus status;
  final double distanceAlong;
  final double totalMeters;
  final TrafficBand band;

  /// Speed on the road, before the time multiplier.
  final double roadSpeedMps;

  /// Estimated real seconds to the destination at the current multiplier.
  final double remainingSeconds;

  double get progress =>
      totalMeters <= 0 ? 1 : (distanceAlong / totalMeters).clamp(0.0, 1.0);
  double get roadSpeedKmh => roadSpeedMps * 3.6;
}

/// Moves a virtual traveller along a [SimRoute], adjusting speed for traffic,
/// turns, and arrival. Time is driven externally through [step] so the engine
/// is deterministic and testable.
class RouteSimulator {
  RouteSimulator({
    required SimRoute route,
    required this.config,
    math.Random? random,
  }) : _route = route,
       _random = random ?? math.Random();

  SimRoute _route;
  SimulationConfig config;
  final math.Random _random;

  double _distance = 0;
  double _speed = 0;
  SimStatus _status = SimStatus.running;

  SimRoute get route => _route;
  SimStatus get status => _status;
  double get distanceAlong => _distance;
  double get roadSpeedMps => _speed;

  static const double _jitter = 0.05;
  static const double _minCrawlMps = 0.8;

  double get _accel => math.max(0.4, config.baseSpeedMps / 8);
  double get _decel => _accel * 2;

  void pause() {
    if (_status == SimStatus.running) _status = SimStatus.paused;
  }

  void resume() {
    if (_status == SimStatus.paused) _status = SimStatus.running;
  }

  void restart() {
    _distance = 0;
    _speed = 0;
    _status = SimStatus.running;
  }

  /// Swaps in a refreshed route that starts at the current position.
  void replaceRoute(SimRoute route) {
    _route = route;
    _distance = 0;
    if (_status == SimStatus.finished) _status = SimStatus.running;
  }

  /// Road speed the traveller is aiming for at the current position.
  double targetSpeedMps() {
    var target = config.baseSpeedMps;
    final band = _route.bandAt(_distance);
    if (config.followTraffic) target *= band.speedFactor;

    final lookahead = math.max(30.0, _speed * 4);
    final turn = _route.turnAngleAhead(_distance, lookahead);
    if (turn > 20) {
      target *= (1 - (turn - 20) / 160).clamp(0.3, 1.0);
    }

    final remaining = _route.totalMeters - _distance;
    if (!config.loop) {
      final stopping = math.sqrt(2 * _decel * math.max(0, remaining));
      target = math.min(target, math.max(stopping, _minCrawlMps));
    }
    return target;
  }

  SimSnapshot step(Duration dt, DateTime now) {
    if (_status == SimStatus.running) {
      final secs = dt.inMicroseconds / 1e6 * config.multiplier;
      final jitter = 1 + (_random.nextDouble() * 2 - 1) * _jitter;
      final target = targetSpeedMps() * jitter;
      if (target > _speed) {
        _speed = math.min(target, _speed + _accel * secs);
      } else {
        _speed = math.max(target, _speed - _decel * secs);
      }
      _distance += _speed * secs;
      if (_distance >= _route.totalMeters) {
        if (config.loop) {
          _distance = 0;
        } else {
          _distance = _route.totalMeters;
          _speed = 0;
          _status = SimStatus.finished;
        }
      }
    }
    return snapshot(now);
  }

  SimSnapshot snapshot(DateTime now) {
    final moving = _status == SimStatus.running;
    final pos = _route.positionAt(_distance);
    final roadSpeed = moving ? _speed : 0.0;
    return SimSnapshot(
      fix: GeoFix(
        latitude: pos.latitude,
        longitude: pos.longitude,
        accuracy: 3 + _random.nextDouble() * 2,
        heading: _route.bearingAt(_distance),
        speed: roadSpeed * config.multiplier,
        timestamp: now.toUtc(),
        isMock: true,
      ),
      status: _status,
      distanceAlong: _distance,
      totalMeters: _route.totalMeters,
      band: _route.bandAt(_distance),
      roadSpeedMps: roadSpeed,
      remainingSeconds: _estimateRemainingSeconds(),
    );
  }

  double _estimateRemainingSeconds() {
    if (_status == SimStatus.finished) return 0;
    final base = config.baseSpeedMps;
    var seconds = 0.0;
    final start = _route.segmentAt(_distance);
    for (var i = start; i < _route.points.length - 1; i++) {
      final a = i == start ? _route.positionAt(_distance) : _route.points[i];
      final len = a.distanceTo(_route.points[i + 1]);
      final factor = config.followTraffic
          ? _route.segmentBands[i].speedFactor
          : 1.0;
      seconds += len / math.max(_minCrawlMps, base * factor);
    }
    return seconds / config.multiplier;
  }
}
