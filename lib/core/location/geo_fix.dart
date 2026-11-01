import 'dart:math' as math;

import 'package:equatable/equatable.dart';

/// A plain latitude/longitude pair used by the location layer.
class GeoCoord extends Equatable {
  const GeoCoord(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  static const double _earthRadius = 6371000.0;

  static double _rad(double d) => d * math.pi / 180;
  static double _deg(double r) => r * 180 / math.pi;

  /// Great-circle distance in metres.
  double distanceTo(GeoCoord other) {
    final dLat = _rad(other.latitude - latitude);
    final dLon = _rad(other.longitude - longitude);
    final h =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(latitude)) *
            math.cos(_rad(other.latitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return _earthRadius * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  /// Initial bearing towards [other] in degrees, 0..360 (0 = north).
  double bearingTo(GeoCoord other) {
    final phi1 = _rad(latitude);
    final phi2 = _rad(other.latitude);
    final dLon = _rad(other.longitude - longitude);
    final y = math.sin(dLon) * math.cos(phi2);
    final x =
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLon);
    return (_deg(math.atan2(y, x)) + 360) % 360;
  }

  /// Linear interpolation; accurate enough for the short segments of a route.
  GeoCoord lerp(GeoCoord other, double t) => GeoCoord(
    latitude + (other.latitude - latitude) * t,
    longitude + (other.longitude - longitude) * t,
  );

  Map<String, double> toJson() => {'lat': latitude, 'lng': longitude};

  static GeoCoord? fromJson(Object? json) {
    if (json is! Map) return null;
    final lat = json['lat'];
    final lng = json['lng'];
    if (lat is! num || lng is! num) return null;
    return GeoCoord(lat.toDouble(), lng.toDouble());
  }

  @override
  List<Object?> get props => [latitude, longitude];

  @override
  String toString() =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
}

/// One position reading, real or simulated.
class GeoFix extends Equatable {
  const GeoFix({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy = 5,
    this.altitude = 0,
    this.heading = 0,
    this.speed = 0,
    this.isMock = false,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final double altitude;

  /// Degrees clockwise from north.
  final double heading;

  /// Metres per second.
  final double speed;
  final DateTime timestamp;

  /// True when produced by the in-app mock rather than the device GPS.
  final bool isMock;

  GeoCoord get coord => GeoCoord(latitude, longitude);

  @override
  List<Object?> get props => [
    latitude,
    longitude,
    accuracy,
    altitude,
    heading,
    speed,
    timestamp,
    isMock,
  ];
}
