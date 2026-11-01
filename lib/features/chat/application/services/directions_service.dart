import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/location/maps/google_api_auth.dart';
import '../../../../core/location/mock/sim_route.dart';
import '../../domain/entities/geo_share.dart';

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
    if (!await _auth.isConfigured) {
      return GeoShare.route(
        origin: origin,
        destination: destination,
        label: label,
        path: [origin, destination],
        mode: mode.name,
      );
    }
    Map<String, Object> waypoint(GeoPoint p) => {
      'location': {
        'latLng': {'latitude': p.latitude, 'longitude': p.longitude},
      },
    };
    final response = await _client
        .post(
          Uri.https('routes.googleapis.com', '/directions/v2:computeRoutes'),
          headers: await _auth.headers(
            fieldMask:
                'routes.distanceMeters,routes.duration,'
                'routes.polyline.encodedPolyline',
          ),
          body: jsonEncode({
            'origin': waypoint(origin),
            'destination': waypoint(destination),
            'travelMode': mode.routesTravelMode,
          }),
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
    final route = routes.first as Map<String, dynamic>;
    final encoded =
        (route['polyline'] as Map<String, dynamic>)['encodedPolyline']
            as String;
    return GeoShare.route(
      origin: origin,
      destination: destination,
      label: label,
      path: decodePolyline(encoded),
      distanceMeters: ((route['distanceMeters'] as num?) ?? 0).toDouble(),
      durationSeconds: _parseDurationSeconds(route['duration']),
      mode: mode.name,
    );
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
