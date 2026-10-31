import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/entities/geo_share.dart';

/// Resolves a driving route between two points with the Google Directions API.
///
/// The key comes from `GOOGLE_DIRECTIONS_API_KEY` in `.api_keys.json`. Without
/// it the route falls back to a straight line, so sharing still works.
class DirectionsService {
  DirectionsService({http.Client? client, String? apiKey})
    : _client = client ?? http.Client(),
      _apiKey =
          apiKey ?? const String.fromEnvironment('GOOGLE_DIRECTIONS_API_KEY');

  final http.Client _client;
  final String _apiKey;

  bool get isConfigured => _apiKey.isNotEmpty;

  Future<GeoShare> fetchRoute({
    required GeoPoint origin,
    required GeoPoint destination,
    String label = '',
  }) async {
    if (!isConfigured) {
      return GeoShare.route(
        origin: origin,
        destination: destination,
        label: label,
        path: [origin, destination],
      );
    }
    final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
      'origin': '${origin.latitude},${origin.longitude}',
      'destination': '${destination.latitude},${destination.longitude}',
      'key': _apiKey,
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw DirectionsException('Directions request failed.');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final status = json['status'] as String?;
    if (status != 'OK') {
      throw DirectionsException(
        status == 'ZERO_RESULTS'
            ? 'No route found between these points.'
            : 'Directions unavailable ($status).',
      );
    }
    final route = (json['routes'] as List).first as Map<String, dynamic>;
    final leg = (route['legs'] as List).first as Map<String, dynamic>;
    final encoded =
        (route['overview_polyline'] as Map<String, dynamic>)['points']
            as String;
    return GeoShare.route(
      origin: origin,
      destination: destination,
      label: label,
      path: decodePolyline(encoded),
      distanceMeters: ((leg['distance'] as Map)['value'] as num).toDouble(),
      durationSeconds: ((leg['duration'] as Map)['value'] as num).toInt(),
    );
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
