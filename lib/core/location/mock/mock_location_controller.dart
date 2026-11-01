import 'dart:async';

import 'package:flutter/foundation.dart';

import '../geo_fix.dart';
import 'route_simulator.dart';
import 'sim_route.dart';
import 'system_mock_bridge.dart';

enum MockMode { off, fixed, route }

/// Builds a fresh route from the current simulated position, used to refresh
/// traffic during a long simulation.
typedef RouteRefresher = Future<SimRoute> Function(GeoCoord from);

/// Owns mock-location state: a fixed point or a running route simulation,
/// and optionally mirrors it to Android's system location providers.
///
/// State lives in memory only, so the app always restarts on the real GPS.
class MockLocationController extends ChangeNotifier {
  MockLocationController({
    SystemMockBridge? systemBridge,
    this.tick = const Duration(seconds: 1),
    DateTime Function()? clock,
  }) : _bridge = systemBridge ?? SystemMockBridge(),
       _clock = clock ?? DateTime.now {
    _bridge.onStopRequested = () => unawaited(useRealGps());
  }

  final SystemMockBridge _bridge;
  final Duration tick;
  final DateTime Function() _clock;

  final _fixes = StreamController<GeoFix>.broadcast();
  Timer? _timer;
  MockMode _mode = MockMode.off;
  GeoFix? _latest;
  GeoFix? _fixedTemplate;
  RouteSimulator? _simulator;
  SimSnapshot? _snapshot;
  RouteRefresher? _refresher;
  DateTime? _lastRefreshAt;
  bool _refreshing = false;
  String? _refreshError;

  bool _systemWide = false;
  bool _systemWideRunning = false;
  String? _systemWideError;
  bool _disposed = false;

  MockMode get mode => _mode;
  bool get isActive => _mode != MockMode.off;
  GeoFix? get latest => _latest;
  RouteSimulator? get simulator => _simulator;
  SimSnapshot? get snapshot => _snapshot;
  bool get systemWide => _systemWide;
  bool get systemWideRunning => _systemWideRunning;
  String? get systemWideError => _systemWideError;
  String? get trafficRefreshError => _refreshError;
  bool get isRefreshingTraffic => _refreshing;
  SystemMockBridge get systemBridge => _bridge;

  /// Mock fixes, emitted every [tick] while mock mode is on.
  Stream<GeoFix> get fixes => _fixes.stream;

  /// Short human summary for the banner and notification.
  String get statusLabel {
    switch (_mode) {
      case MockMode.off:
        return 'Real GPS';
      case MockMode.fixed:
        final f = _latest;
        return f == null ? 'Fixed point' : 'Fixed point · ${f.coord}';
      case MockMode.route:
        final s = _snapshot;
        if (s == null) return 'Route simulation';
        final pct = (s.progress * 100).round();
        final state = switch (s.status) {
          SimStatus.paused => 'paused',
          SimStatus.finished => 'arrived',
          SimStatus.running =>
            '${s.roadSpeedKmh.round()} km/h'
                '${s.band == TrafficBand.unknown ? '' : ' (${s.band.label.toLowerCase()})'}',
        };
        return 'Route $pct% · $state';
    }
  }

  void enableFixed(GeoCoord point, {double accuracy = 5, double altitude = 0}) {
    _stopSimulation();
    _mode = MockMode.fixed;
    _fixedTemplate = GeoFix(
      latitude: point.latitude,
      longitude: point.longitude,
      accuracy: accuracy,
      altitude: altitude,
      timestamp: _clock().toUtc(),
      isMock: true,
    );
    _startTicking();
  }

  void startRoute(
    SimRoute route,
    SimulationConfig config, {
    RouteRefresher? refresher,
  }) {
    _stopSimulation();
    _mode = MockMode.route;
    _simulator = RouteSimulator(route: route, config: config);
    _refresher = refresher;
    _lastRefreshAt = _clock();
    _refreshError = null;
    _startTicking();
  }

  void pauseRoute() {
    _simulator?.pause();
    _emit();
  }

  void resumeRoute() {
    _simulator?.resume();
    _emit();
  }

  void restartRoute() {
    _simulator?.restart();
    _emit();
  }

  void updateSimulationConfig(SimulationConfig config) {
    final sim = _simulator;
    if (sim == null) return;
    sim.config = config;
    notifyListeners();
  }

  /// Turns mock off; consumers switch straight back to the device GPS.
  Future<void> useRealGps() async {
    if (_mode == MockMode.off && !_systemWideRunning) return;
    _stopSimulation();
    _mode = MockMode.off;
    _latest = null;
    _fixedTemplate = null;
    await _stopSystemWide();
    if (!_disposed) notifyListeners();
  }

  /// Mirrors mock fixes into Android's location providers when enabled.
  Future<void> setSystemWide(bool enabled) async {
    _systemWide = enabled;
    _systemWideError = null;
    if (!enabled) {
      await _stopSystemWide();
    } else if (isActive) {
      await _startSystemWide();
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> _startSystemWide() async {
    if (_systemWideRunning || !_systemWide) return;
    final availability = await _bridge.availability();
    if (availability != SystemMockAvailability.ready) {
      _systemWideError = availability == SystemMockAvailability.unsupported
          ? 'System-wide mock is only available on Android.'
          : 'Select this app under Developer options → '
                'Select mock location app.';
      _systemWide = false;
      return;
    }
    try {
      await _bridge.start(status: statusLabel);
      _systemWideRunning = true;
      final fix = _latest;
      if (fix != null) await _bridge.push(fix, status: statusLabel);
    } catch (e) {
      _systemWideError = 'Could not start system mock: $e';
      _systemWide = false;
    }
  }

  Future<void> _stopSystemWide() async {
    if (!_systemWideRunning) return;
    _systemWideRunning = false;
    try {
      await _bridge.stop();
    } catch (e) {
      debugPrint('System mock stop failed: $e');
    }
  }

  void _startTicking() {
    _timer?.cancel();
    _emit();
    _timer = Timer.periodic(tick, (_) => _onTick());
    if (_systemWide && !_systemWideRunning) {
      unawaited(_startSystemWide().then((_) => _safeNotify()));
    }
  }

  void _stopSimulation() {
    _timer?.cancel();
    _timer = null;
    _simulator = null;
    _snapshot = null;
    _refresher = null;
  }

  void _onTick() {
    final sim = _simulator;
    if (_mode == MockMode.route && sim != null) {
      _snapshot = sim.step(tick, _clock());
      _maybeRefreshTraffic();
    }
    _emit();
  }

  /// Publishes the current fix without advancing the simulation.
  void _emit() {
    final now = _clock();
    switch (_mode) {
      case MockMode.off:
        return;
      case MockMode.fixed:
        final t = _fixedTemplate!;
        _latest = GeoFix(
          latitude: t.latitude,
          longitude: t.longitude,
          accuracy: t.accuracy,
          altitude: t.altitude,
          timestamp: now.toUtc(),
          isMock: true,
        );
      case MockMode.route:
        final sim = _simulator!;
        _snapshot = sim.snapshot(now);
        _latest = _snapshot!.fix;
    }
    final fix = _latest!;
    if (!_fixes.isClosed) _fixes.add(fix);
    if (_systemWideRunning) {
      unawaited(
        _bridge.push(fix, status: statusLabel).catchError((Object e) {
          _systemWideError = 'System mock stopped: $e';
          _systemWideRunning = false;
          _systemWide = false;
          _safeNotify();
        }),
      );
    }
    _safeNotify();
  }

  void _maybeRefreshTraffic() {
    final sim = _simulator;
    final refresher = _refresher;
    final every = sim?.config.trafficRefresh;
    if (sim == null ||
        refresher == null ||
        every == null ||
        _refreshing ||
        sim.status != SimStatus.running ||
        !sim.config.profile.supportsTraffic) {
      return;
    }
    final last = _lastRefreshAt;
    if (last != null && _clock().difference(last) < every) return;
    _lastRefreshAt = _clock();
    unawaited(refreshTrafficNow());
  }

  /// Re-requests traffic for the rest of the route from the current position.
  Future<void> refreshTrafficNow() async {
    final sim = _simulator;
    final refresher = _refresher;
    if (sim == null || refresher == null || _refreshing) return;
    _refreshing = true;
    _safeNotify();
    try {
      final from = sim.route.positionAt(sim.distanceAlong);
      final fresh = await refresher(from);
      // A straight-line fallback would discard real road geometry.
      if (identical(_simulator, sim) &&
          fresh.source != SimRouteSource.straightLine) {
        sim.replaceRoute(fresh);
        _refreshError = null;
      } else if (fresh.warning != null) {
        _refreshError = fresh.warning;
      }
    } catch (e) {
      _refreshError = '$e';
    } finally {
      _refreshing = false;
      _lastRefreshAt = _clock();
      _safeNotify();
    }
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _bridge.onStopRequested = null;
    unawaited(_stopSystemWide());
    _fixes.close();
    super.dispose();
  }
}
