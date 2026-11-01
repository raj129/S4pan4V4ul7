import 'dart:convert';

import '../geo_fix.dart';
import 'route_simulator.dart';
import 'sim_route.dart';

/// Last-used mock settings, saved so mock mode can be re-enabled quickly.
///
/// Whether mock mode is *on* is deliberately not stored: every app start
/// begins on the real GPS.
class MockLocationPreferences {
  const MockLocationPreferences({
    this.fixedPoint,
    this.fixedAccuracy = 5,
    this.routeOrigin,
    this.routeDestination,
    this.profile = TravelProfile.drive,
    this.baseSpeedKmh = 0,
    this.multiplier = 1,
    this.loop = false,
    this.followTraffic = true,
    this.trafficRefreshMinutes = 5,
    this.systemWide = false,
  });

  final GeoCoord? fixedPoint;
  final double fixedAccuracy;
  final GeoCoord? routeOrigin;
  final GeoCoord? routeDestination;
  final TravelProfile profile;

  /// 0 means "use the profile default".
  final double baseSpeedKmh;
  final double multiplier;
  final bool loop;
  final bool followTraffic;

  /// 0 disables periodic traffic refresh.
  final int trafficRefreshMinutes;
  final bool systemWide;

  SimulationConfig toSimulationConfig() => SimulationConfig(
    profile: profile,
    baseSpeedKmh: baseSpeedKmh,
    multiplier: multiplier,
    loop: loop,
    followTraffic: followTraffic,
    trafficRefresh: trafficRefreshMinutes > 0
        ? Duration(minutes: trafficRefreshMinutes)
        : null,
  );

  MockLocationPreferences copyWith({
    GeoCoord? fixedPoint,
    double? fixedAccuracy,
    GeoCoord? routeOrigin,
    GeoCoord? routeDestination,
    TravelProfile? profile,
    double? baseSpeedKmh,
    double? multiplier,
    bool? loop,
    bool? followTraffic,
    int? trafficRefreshMinutes,
    bool? systemWide,
  }) => MockLocationPreferences(
    fixedPoint: fixedPoint ?? this.fixedPoint,
    fixedAccuracy: fixedAccuracy ?? this.fixedAccuracy,
    routeOrigin: routeOrigin ?? this.routeOrigin,
    routeDestination: routeDestination ?? this.routeDestination,
    profile: profile ?? this.profile,
    baseSpeedKmh: baseSpeedKmh ?? this.baseSpeedKmh,
    multiplier: multiplier ?? this.multiplier,
    loop: loop ?? this.loop,
    followTraffic: followTraffic ?? this.followTraffic,
    trafficRefreshMinutes: trafficRefreshMinutes ?? this.trafficRefreshMinutes,
    systemWide: systemWide ?? this.systemWide,
  );

  String encode() => jsonEncode({
    if (fixedPoint != null) 'fixed': fixedPoint!.toJson(),
    'fixedAcc': fixedAccuracy,
    if (routeOrigin != null) 'a': routeOrigin!.toJson(),
    if (routeDestination != null) 'b': routeDestination!.toJson(),
    'profile': profile.name,
    'speed': baseSpeedKmh,
    'mult': multiplier,
    'loop': loop,
    'traffic': followTraffic,
    'refresh': trafficRefreshMinutes,
    'system': systemWide,
  });

  static MockLocationPreferences decode(String? raw) {
    if (raw == null || raw.isEmpty) return const MockLocationPreferences();
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      double num0(String key, double fallback) =>
          (json[key] as num?)?.toDouble() ?? fallback;
      return MockLocationPreferences(
        fixedPoint: GeoCoord.fromJson(json['fixed']),
        fixedAccuracy: num0('fixedAcc', 5),
        routeOrigin: GeoCoord.fromJson(json['a']),
        routeDestination: GeoCoord.fromJson(json['b']),
        profile: TravelProfile.fromName(json['profile'] as String?),
        baseSpeedKmh: num0('speed', 0),
        multiplier: num0('mult', 1).clamp(0.25, 20),
        loop: json['loop'] == true,
        followTraffic: json['traffic'] != false,
        trafficRefreshMinutes: (json['refresh'] as num?)?.toInt() ?? 5,
        systemWide: json['system'] == true,
      );
    } catch (_) {
      return const MockLocationPreferences();
    }
  }
}
