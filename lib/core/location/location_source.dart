import 'dart:io' show Platform;

import 'package:geolocator/geolocator.dart';

import 'geo_fix.dart';

/// How often a position stream should report.
class LocationUpdateConfig {
  const LocationUpdateConfig({
    this.distanceFilterMeters = 0,
    this.interval = const Duration(seconds: 1),
    this.backgroundNotification = false,
  });

  final int distanceFilterMeters;
  final Duration interval;

  /// Keeps the stream alive in the background via an ongoing notification
  /// (Android only).
  final bool backgroundNotification;
}

/// Anything that can produce device positions.
abstract class LocationSource {
  Future<bool> isServiceEnabled();
  Future<GeoFix?> lastKnown();
  Future<GeoFix> current({Duration? timeLimit});
  Stream<GeoFix> updates([LocationUpdateConfig config]);
}

/// The real device GPS, via Geolocator.
class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  static GeoFix _fromPosition(Position p) => GeoFix(
    latitude: p.latitude,
    longitude: p.longitude,
    accuracy: p.accuracy,
    altitude: p.altitude,
    heading: p.heading,
    speed: p.speed,
    timestamp: p.timestamp.toUtc(),
  );

  @override
  Future<bool> isServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<GeoFix?> lastKnown() async {
    final p = await Geolocator.getLastKnownPosition();
    return p == null ? null : _fromPosition(p);
  }

  @override
  Future<GeoFix> current({Duration? timeLimit}) async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: timeLimit,
      ),
    );
    return _fromPosition(p);
  }

  @override
  Stream<GeoFix> updates([
    LocationUpdateConfig config = const LocationUpdateConfig(),
  ]) {
    final LocationSettings settings = Platform.isAndroid
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: config.distanceFilterMeters,
            intervalDuration: config.interval,
            foregroundNotificationConfig: config.backgroundNotification
                ? const ForegroundNotificationConfig(
                    notificationTitle: 'Calculator',
                    notificationText: 'Syncing in background',
                    notificationChannelName: 'Calculator notifications',
                    enableWakeLock: true,
                    // Updates are uploaded as they arrive; without this the
                    // radio may sleep with the screen off and stall sharing.
                    enableWifiLock: true,
                    setOngoing: true,
                  )
                : null,
          )
        : LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: config.distanceFilterMeters,
          );
    return Geolocator.getPositionStream(
      locationSettings: settings,
    ).map(_fromPosition);
  }
}
