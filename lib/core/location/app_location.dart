import 'dart:async';

import 'geo_fix.dart';
import 'location_source.dart';
import 'mock/mock_location_controller.dart';

/// Single entry point for device location in the app.
///
/// It hands out the real GPS or the mock position depending on
/// [MockLocationController], and switches live streams immediately when the
/// mode changes, so turning mock off goes straight back to the real GPS.
class AppLocation implements LocationSource {
  AppLocation({
    LocationSource real = const GeolocatorLocationSource(),
    MockLocationController? mock,
  }) : _real = real,
       mock = mock ?? MockLocationController();

  static AppLocation? _instance;

  /// The process-wide provider. Tests may replace it.
  static AppLocation get instance => _instance ??= AppLocation();
  static set instance(AppLocation value) => _instance = value;

  final LocationSource _real;
  final MockLocationController mock;

  bool get isMocking => mock.isActive;

  /// The device GPS, bypassing any mock.
  LocationSource get real => _real;

  @override
  Future<bool> isServiceEnabled() async =>
      mock.isActive || await _real.isServiceEnabled();

  @override
  Future<GeoFix?> lastKnown() async =>
      mock.isActive ? mock.latest : _real.lastKnown();

  @override
  Future<GeoFix> current({Duration? timeLimit}) async {
    if (mock.isActive) {
      final fix = mock.latest;
      if (fix != null) return fix;
      return mock.fixes.first;
    }
    return _real.current(timeLimit: timeLimit);
  }

  @override
  Stream<GeoFix> updates([
    LocationUpdateConfig config = const LocationUpdateConfig(),
  ]) {
    // ignore: close_sinks - returned as the stream; closed in onCancel.
    late StreamController<GeoFix> out;
    StreamSubscription<GeoFix>? inner;
    bool? listeningToMock;
    GeoFix? lastSent;

    bool shouldSend(GeoFix fix) {
      final prev = lastSent;
      if (prev == null || prev.isMock != fix.isMock) return true;
      if (fix.timestamp.difference(prev.timestamp) < config.interval) {
        return false;
      }
      return config.distanceFilterMeters <= 0 ||
          prev.coord.distanceTo(fix.coord) >= config.distanceFilterMeters;
    }

    void attach() {
      final useMock = mock.isActive;
      if (listeningToMock == useMock && inner != null) return;
      listeningToMock = useMock;
      unawaited(inner?.cancel());
      if (useMock) {
        inner = mock.fixes.listen((fix) {
          if (shouldSend(fix)) {
            lastSent = fix;
            out.add(fix);
          }
        });
        final now = mock.latest;
        if (now != null && shouldSend(now)) {
          lastSent = now;
          out.add(now);
        }
      } else {
        inner = _real.updates(config).listen((fix) {
          lastSent = fix;
          out.add(fix);
        }, onError: out.addError);
      }
    }

    void onModeChanged() {
      if (listeningToMock != mock.isActive) attach();
    }

    out = StreamController<GeoFix>(
      onListen: () {
        mock.addListener(onModeChanged);
        attach();
      },
      onPause: () => inner?.pause(),
      onResume: () => inner?.resume(),
      onCancel: () async {
        mock.removeListener(onModeChanged);
        await inner?.cancel();
        inner = null;
      },
    );
    return out.stream;
  }
}
