import 'dart:convert';

import 'package:http/http.dart' as http;

import '../geo_fix.dart';
import '../maps/google_api_auth.dart';
import 'polyline_codec.dart';
import 'sim_route.dart';

/// Builds a [SimRoute] between two points, preferring per-segment live traffic
/// from the Google Routes API.
///
/// Uses the Maps key via [GoogleApiAuth] (Dart define or the Android
/// manifest). Falls back to a straight line, so simulation always works even
/// without a key or connectivity.
class TrafficRouteService {
  TrafficRouteService({
    http.Client? client,
    String? apiKey,
    GoogleApiAuth? auth,
  }) : _client = client ?? http.Client(),
       _auth =
           auth ??
           (apiKey == null
               ? GoogleApiAuth.instance
               : GoogleApiAuth(apiKey: apiKey, isAndroid: false));

  static final Uri routesUri = Uri.https(
    'routes.googleapis.com',
    '/directions/v2:computeRoutes',
  );
  static const fieldMask =
      'routes.distanceMeters,routes.duration,routes.polyline.encodedPolyline,'
      'routes.travelAdvisory.speedReadingIntervals';
  static const _timeout = Duration(seconds: 15);

  final http.Client _client;
  final GoogleApiAuth _auth;

  Future<bool> get isConfigured => _auth.isConfigured;

  Future<SimRoute> fetch({
    required GeoCoord origin,
    required GeoCoord destination,
    TravelProfile profile = TravelProfile.drive,
  }) async {
    if (!await _auth.isConfigured) {
      return SimRoute.straightLine(
        origin,
        destination,
        warning: 'No Google Maps API key found in this build.',
      );
    }
    try {
      return await _fetchRoutes(origin, destination, profile);
    } catch (e) {
      return SimRoute.straightLine(
        origin,
        destination,
        warning: 'Routes API: $e',
      );
    }
  }

  Future<SimRoute> _fetchRoutes(
    GeoCoord origin,
    GeoCoord destination,
    TravelProfile profile,
  ) async {
    Map<String, Object> waypoint(GeoCoord c) => {
      'location': {
        'latLng': {'latitude': c.latitude, 'longitude': c.longitude},
      },
    };
    final body = <String, Object>{
      'origin': waypoint(origin),
      'destination': waypoint(destination),
      'travelMode': profile.routesTravelMode,
      'polylineQuality': 'HIGH_QUALITY',
      if (profile.supportsTraffic) ...{
        'routingPreference': 'TRAFFIC_AWARE_OPTIMAL',
        'extraComputations': ['TRAFFIC_ON_POLYLINE'],
      },
    };
    final response = await _client
        .post(
          routesUri,
          headers: await _auth.headers(fieldMask: fieldMask),
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    if (response.statusCode != 200) {
      throw TrafficRouteException(
        GoogleApiAuth.describeFailure(
          response.statusCode,
          response.body,
          api: 'Routes API',
        ),
      );
    }
    return parseRoutesResponse(response.body);
  }

  /// Parses a `computeRoutes` response body. Public for tests.
  static SimRoute parseRoutesResponse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final routes = json['routes'] as List?;
    if (routes == null || routes.isEmpty) {
      throw TrafficRouteException('No route found between these points.');
    }
    final route = routes.first as Map<String, dynamic>;
    final encoded =
        (route['polyline'] as Map<String, dynamic>?)?['encodedPolyline']
            as String?;
    if (encoded == null || encoded.isEmpty) {
      throw TrafficRouteException('Route had no polyline.');
    }
    final points = PolylineCodec.decode(encoded);
    if (points.length < 2) {
      throw TrafficRouteException('Route polyline too short.');
    }
    final bands = List<TrafficBand>.filled(
      points.length - 1,
      TrafficBand.unknown,
    );
    final intervals =
        ((route['travelAdvisory']
                as Map<String, dynamic>?)?['speedReadingIntervals']
            as List?) ??
        const [];
    for (final raw in intervals) {
      final interval = raw as Map<String, dynamic>;
      // proto3 JSON omits zero-valued fields, so a missing start means 0.
      final start = (interval['startPolylinePointIndex'] as num?)?.toInt() ?? 0;
      final end =
          (interval['endPolylinePointIndex'] as num?)?.toInt() ??
          points.length - 1;
      final band = TrafficBand.fromApi(interval['speed'] as String?);
      for (var i = start; i < end && i < bands.length; i++) {
        if (i >= 0) bands[i] = band;
      }
    }
    final hasTraffic = bands.any((b) => b != TrafficBand.unknown);
    return SimRoute(
      points: points,
      segmentBands: bands,
      source: hasTraffic
          ? SimRouteSource.routesWithTraffic
          : SimRouteSource.routes,
      apiDurationSeconds: _parseDuration(route['duration']),
    );
  }

  static int? _parseDuration(Object? raw) {
    if (raw is! String || !raw.endsWith('s')) return null;
    return double.tryParse(raw.substring(0, raw.length - 1))?.round();
  }

  void dispose() => _client.close();
}

class TrafficRouteException implements Exception {
  TrafficRouteException(this.message);

  final String message;

  @override
  String toString() => message;
}
