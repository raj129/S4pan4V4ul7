import 'dart:convert';
import 'dart:ui' show Color;

import 'package:http/http.dart' as http;

import '../../../../core/location/maps/google_api_auth.dart';
import '../../../../core/location/mock/sim_route.dart';
import '../../domain/entities/geo_share.dart';

/// A traffic-speed interval along a route's polyline.
class RouteTrafficSpan {
  const RouteTrafficSpan({
    required this.startIndex,
    required this.endIndex,
    required this.band,
  });

  final int startIndex;
  final int endIndex;
  final TrafficBand band;
}

/// One step of a transit route (walk or metro/bus/train leg with its line color).
class TransitStepSegment {
  const TransitStepSegment({
    required this.points,
    required this.isTransit,
    this.lineName,
    this.lineColor,
  });

  final List<GeoPoint> points;
  final bool isTransit;
  final String? lineName;
  final Color? lineColor;
}

/// A route option returned by [DirectionsService.fetchRouteOptions], carrying
/// the shareable [GeoShare] plus optional live traffic spans and transit legs.
class RouteOption {
  const RouteOption({
    required this.share,
    this.trafficSpans = const [],
    this.transitSegments = const [],
  });

  final GeoShare share;
  final List<RouteTrafficSpan> trafficSpans;
  final List<TransitStepSegment> transitSegments;
}

/// Resolves a route between two points with the Google Routes API.
///
/// Uses the Maps key via [GoogleApiAuth] (Dart define or the Android
/// manifest). Without a key the route falls back to a straight line, so
/// sharing still works.
class DirectionsService {
  DirectionsService({http.Client? client, String? apiKey, GoogleApiAuth? auth})
    : _client = client ?? http.Client(),
      _auth =
          auth ??
          (apiKey == null
              ? GoogleApiAuth.instance
              : GoogleApiAuth(apiKey: apiKey, isAndroid: false));

  final http.Client _client;
  final GoogleApiAuth _auth;

  Future<bool> get isConfigured => _auth.isConfigured;

  Future<GeoShare> fetchRoute({
    required GeoPoint origin,
    required GeoPoint destination,
    String label = '',
    TravelProfile mode = TravelProfile.drive,
  }) async {
    final routes = await fetchRoutes(
      origin: origin,
      destination: destination,
      label: label,
      mode: mode,
      alternatives: false,
    );
    return routes.first;
  }

  /// Fetches primary and optional alternative routes with traffic-aware
  /// durations when supported by [mode].
  Future<List<GeoShare>> fetchRoutes({
    required GeoPoint origin,
    required GeoPoint destination,
    String label = '',
    TravelProfile mode = TravelProfile.drive,
    bool alternatives = true,
  }) async {
    final options = await fetchRouteOptions(
      origin: origin,
      destination: destination,
      label: label,
      mode: mode,
      alternatives: alternatives,
    );
    return [for (final o in options) o.share];
  }

  /// Fetches [RouteOption]s with traffic-speed intervals (for driving/2-wheeler)
  /// and colored metro/transit leg details (for transit).
  Future<List<RouteOption>> fetchRouteOptions({
    required GeoPoint origin,
    required GeoPoint destination,
    String label = '',
    TravelProfile mode = TravelProfile.drive,
    bool alternatives = true,
  }) async {
    if (!await _auth.isConfigured) {
      return [
        RouteOption(
          share: GeoShare.route(
            origin: origin,
            destination: destination,
            label: label,
            path: [origin, destination],
            mode: mode.name,
          ),
        ),
      ];
    }
    Map<String, Object> waypoint(GeoPoint p) => {
      'location': {
        'latLng': {'latitude': p.latitude, 'longitude': p.longitude},
      },
    };
    final isTransit = mode == TravelProfile.transit;
    final body = <String, Object>{
      'origin': waypoint(origin),
      'destination': waypoint(destination),
      'travelMode': mode.routesTravelMode,
      if (alternatives && !isTransit) 'computeAlternativeRoutes': true,
      if (mode.supportsTraffic) ...{
        'routingPreference': 'TRAFFIC_AWARE',
        'extraComputations': ['TRAFFIC_ON_POLYLINE'],
      },
    };
    final fieldMask = isTransit
        ? 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,'
              'routes.legs.steps.travelMode,'
              'routes.legs.steps.polyline.encodedPolyline,'
              'routes.legs.steps.transitDetails.transitLine.nameShort,'
              'routes.legs.steps.transitDetails.transitLine.name,'
              'routes.legs.steps.transitDetails.transitLine.color'
        : mode.supportsTraffic
        ? 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,'
              'routes.travelAdvisory.speedReadingIntervals'
        : 'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline';
    final response = await _client
        .post(
          Uri.https('routes.googleapis.com', '/directions/v2:computeRoutes'),
          headers: await _auth.headers(fieldMask: fieldMask),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw DirectionsException(
        GoogleApiAuth.describeFailure(
          response.statusCode,
          response.body,
          api: 'Routes API',
        ),
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw DirectionsException('No route found between these points.');
    }
    return [
      for (final raw in routes)
        if (raw is Map<String, dynamic>)
          if ((raw['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
              case final String encoded)
            _parseRouteOption(
              raw: raw,
              encoded: encoded,
              origin: origin,
              destination: destination,
              label: label,
              mode: mode,
            ),
    ];
  }

  static RouteOption _parseRouteOption({
    required Map<String, dynamic> raw,
    required String encoded,
    required GeoPoint origin,
    required GeoPoint destination,
    required String label,
    required TravelProfile mode,
  }) {
    final points = decodePolyline(encoded);
    final share = GeoShare.route(
      origin: origin,
      destination: destination,
      label: label,
      path: points,
      distanceMeters: ((raw['distanceMeters'] as num?) ?? 0).toDouble(),
      durationSeconds: _parseDurationSeconds(raw['duration']),
      mode: mode.name,
    );

    final spans = <RouteTrafficSpan>[];
    final intervals =
        ((raw['travelAdvisory'] as Map<String, dynamic>?)?['speedReadingIntervals']
            as List?) ??
        const [];
    for (final item in intervals) {
      if (item is! Map<String, dynamic>) continue;
      final start = (item['startPolylinePointIndex'] as num?)?.toInt() ?? 0;
      final end =
          (item['endPolylinePointIndex'] as num?)?.toInt() ??
          points.length - 1;
      final band = TrafficBand.fromApi(item['speed'] as String?);
      if (end > start) {
        spans.add(
          RouteTrafficSpan(startIndex: start, endIndex: end, band: band),
        );
      }
    }

    final transitSegments = <TransitStepSegment>[];
    final legs = (raw['legs'] as List?) ?? const [];
    for (final leg in legs) {
      if (leg is! Map<String, dynamic>) continue;
      final steps = (leg['steps'] as List?) ?? const [];
      for (final step in steps) {
        if (step is! Map<String, dynamic>) continue;
        final stepPoly =
            (step['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
                as String?;
        if (stepPoly == null || stepPoly.isEmpty) continue;
        final stepPoints = decodePolyline(stepPoly);
        if (stepPoints.length < 2) continue;
        final transitDetails = step['transitDetails'] as Map<String, dynamic>?;
        final line = transitDetails?['transitLine'] as Map<String, dynamic>?;
        final lineName =
            (line?['nameShort'] as String?) ?? (line?['name'] as String?);
        final lineColor = _parseHexColor(line?['color'] as String?);
        transitSegments.add(
          TransitStepSegment(
            points: stepPoints,
            isTransit: transitDetails != null,
            lineName: lineName,
            lineColor: lineColor,
          ),
        );
      }
    }

    return RouteOption(
      share: share,
      trafficSpans: spans,
      transitSegments: transitSegments,
    );
  }

  static Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.startsWith('#') ? hex.substring(1) : hex;
    if (clean.length == 6) {
      final value = int.tryParse('FF$clean', radix: 16);
      return value == null ? null : Color(value);
    }
    if (clean.length == 8) {
      final value = int.tryParse(clean, radix: 16);
      return value == null ? null : Color(value);
    }
    return null;
  }

  /// Parses a protobuf duration such as `"321s"`.
  static int _parseDurationSeconds(Object? raw) {
    if (raw is! String || !raw.endsWith('s')) return 0;
    return double.tryParse(raw.substring(0, raw.length - 1))?.round() ?? 0;
  }

  /// Decodes a Google encoded polyline.
  static List<GeoPoint> decodePolyline(String encoded) {
    final points = <GeoPoint>[];
    var index = 0;
    var lat = 0;
    var lng = 0;
    while (index < encoded.length) {
      var shift = 0;
      var result = 0;
      int byte;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      shift = 0;
      result = 0;
      do {
        byte = encoded.codeUnitAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : result >> 1;
      points.add(GeoPoint(lat / 1e5, lng / 1e5));
    }
    return points;
  }

  void dispose() => _client.close();
}

class DirectionsException implements Exception {
  DirectionsException(this.message);

  final String message;

  @override
  String toString() => message;
}
