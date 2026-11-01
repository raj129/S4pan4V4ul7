import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/location/maps/google_api_auth.dart';
import '../../domain/entities/geo_share.dart';

class PlaceResult {
  const PlaceResult({
    required this.name,
    required this.address,
    required this.point,
  });

  final String name;
  final String address;
  final GeoPoint point;
}

/// Searches places by text with the Google Places API (New) Text Search,
/// falling back to the Geocoding API when Places is unavailable.
///
/// Uses the Maps key via [GoogleApiAuth] (Dart define or the Android
/// manifest). Without a key [isConfigured] is false.
class PlaceSearchService {
  PlaceSearchService({http.Client? client, String? apiKey, GoogleApiAuth? auth})
    : _client = client ?? http.Client(),
      _auth =
          auth ??
          (apiKey == null
              ? GoogleApiAuth.instance
              : GoogleApiAuth(apiKey: apiKey, isAndroid: false));

  final http.Client _client;
  final GoogleApiAuth _auth;

  Future<bool> get isConfigured => _auth.isConfigured;

  Future<List<PlaceResult>> search(String query, {GeoPoint? near}) async {
    final text = query.trim();
    if (text.isEmpty || !await _auth.isConfigured) return const [];
    try {
      return await _searchPlaces(text, near);
    } on PlaceSearchException catch (placesError) {
      try {
        return await _geocode(text);
      } on PlaceSearchException {
        throw placesError;
      }
    }
  }

  Future<List<PlaceResult>> _searchPlaces(String text, GeoPoint? near) async {
    final body = <String, Object?>{
      'textQuery': text,
      'pageSize': 8,
      if (near != null)
        'locationBias': {
          'circle': {
            'center': {'latitude': near.latitude, 'longitude': near.longitude},
            'radius': 50000.0,
          },
        },
    };
    final response = await _client
        .post(
          Uri.https('places.googleapis.com', '/v1/places:searchText'),
          headers: await _auth.headers(
            fieldMask:
                'places.displayName,places.formattedAddress,places.location',
          ),
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw PlaceSearchException(
        GoogleApiAuth.describeFailure(
          response.statusCode,
          response.body,
          api: 'Places API (New)',
        ),
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final results = <PlaceResult>[];
    for (final raw in (json['places'] as List? ?? const [])) {
      final place = raw as Map<String, dynamic>;
      final location = place['location'] as Map<String, dynamic>?;
      final lat = (location?['latitude'] as num?)?.toDouble();
      final lng = (location?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      results.add(
        PlaceResult(
          name:
              ((place['displayName'] as Map?)?['text'] as String?) ??
              (place['formattedAddress'] as String? ?? ''),
          address: place['formattedAddress'] as String? ?? '',
          point: GeoPoint(lat, lng),
        ),
      );
    }
    return results;
  }

  Future<List<PlaceResult>> _geocode(String text) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
      'address': text,
      'key': await _auth.key,
    });
    final response = await _client
        .get(uri, headers: await _auth.identityHeaders())
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw PlaceSearchException(
        GoogleApiAuth.describeFailure(
          response.statusCode,
          response.body,
          api: 'Geocoding API',
        ),
      );
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final status = json['status'] as String?;
    if (status == 'ZERO_RESULTS') return const [];
    if (status != 'OK') {
      throw PlaceSearchException(
        GoogleApiAuth.describeFailure(
          response.statusCode,
          response.body,
          api: 'Geocoding API',
        ),
      );
    }
    final results = <PlaceResult>[];
    for (final raw in (json['results'] as List? ?? const [])) {
      final item = raw as Map<String, dynamic>;
      final loc = (item['geometry'] as Map?)?['location'] as Map?;
      final lat = (loc?['lat'] as num?)?.toDouble();
      final lng = (loc?['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      final address = item['formatted_address'] as String? ?? '';
      results.add(
        PlaceResult(
          name: address.split(',').first.trim(),
          address: address,
          point: GeoPoint(lat, lng),
        ),
      );
    }
    return results;
  }

  void dispose() => _client.close();
}

class PlaceSearchException implements Exception {
  PlaceSearchException(this.message);

  final String message;

  @override
  String toString() => message;
}
