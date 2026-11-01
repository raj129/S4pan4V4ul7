import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:photo_vault/core/location/geo_fix.dart';
import 'package:photo_vault/core/location/maps/google_api_auth.dart';
import 'package:photo_vault/core/location/maps/map_widgets.dart';
import 'package:photo_vault/core/location/mock/sim_route.dart';
import 'package:photo_vault/core/location/mock/traffic_route_service.dart';
import 'package:photo_vault/features/chat/application/services/directions_service.dart';
import 'package:photo_vault/features/chat/application/services/place_search_service.dart';
import 'package:photo_vault/features/chat/domain/entities/geo_share.dart';

const _channel = MethodChannel(GoogleApiAuth.channelName);
const _a = GeoPoint(12.97, 77.59);
const _b = GeoPoint(12.98, 77.6);
const _polyline = r'_p~iF~ps|U_ulLnnqC_mqNvxq`@';

void _mockIdentity(Map<String, String>? identity) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, (call) async {
        expect(call.method, 'getMapsApiIdentity');
        return identity;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  group('GoogleApiAuth', () {
    test('falls back to the manifest key and adds app identity', () async {
      _mockIdentity({
        'key': 'manifest-key',
        'package': 'com.x',
        'sha1': 'AB12',
      });
      final auth = GoogleApiAuth(apiKey: '', isAndroid: true);
      expect(await auth.isConfigured, isTrue);
      final headers = await auth.headers(fieldMask: 'routes.duration');
      expect(headers['X-Goog-Api-Key'], 'manifest-key');
      expect(headers['X-Android-Package'], 'com.x');
      expect(headers['X-Android-Cert'], 'AB12');
      expect(headers['X-Goog-FieldMask'], 'routes.duration');
    });

    test('a Dart-defined key wins over the manifest key', () async {
      _mockIdentity({
        'key': 'manifest-key',
        'package': 'com.x',
        'sha1': 'AB12',
      });
      final auth = GoogleApiAuth(apiKey: 'dart-key', isAndroid: true);
      expect((await auth.headers())['X-Goog-Api-Key'], 'dart-key');
    });

    test('is not configured without any key', () async {
      _mockIdentity({'key': '', 'package': 'com.x', 'sha1': ''});
      final auth = GoogleApiAuth(apiKey: '', isAndroid: true);
      expect(await auth.isConfigured, isFalse);
      await expectLater(auth.headers(), throwsStateError);
    });

    test('explains disabled APIs and rejected keys', () {
      expect(
        GoogleApiAuth.describeFailure(
          403,
          '{"error":{"message":"Routes API has not been used in project 1"}}',
          api: 'Routes API',
        ),
        contains('not enabled'),
      );
      expect(
        GoogleApiAuth.describeFailure(403, '', api: 'Places API'),
        contains('SHA-1'),
      );
    });
  });

  group('services', () {
    final routesBody = jsonEncode({
      'routes': [
        {
          'distanceMeters': 1200,
          'duration': '300s',
          'polyline': {'encodedPolyline': _polyline},
        },
      ],
    });

    test('DirectionsService sends the travel mode and app identity', () async {
      _mockIdentity({'key': 'k', 'package': 'com.x', 'sha1': 'AB12'});
      late http.Request seen;
      final service = DirectionsService(
        auth: GoogleApiAuth(apiKey: '', isAndroid: true),
        client: MockClient((req) async {
          seen = req;
          return http.Response(routesBody, 200);
        }),
      );
      final share = await service.fetchRoute(
        origin: _a,
        destination: _b,
        mode: TravelProfile.walk,
      );
      expect(jsonDecode(seen.body)['travelMode'], 'WALK');
      expect(seen.headers['X-Android-Cert'], 'AB12');
      expect(share.mode, 'walk');
      expect(share.distanceMeters, 1200);
      expect(share.durationSeconds, 300);
    });

    test('DirectionsService surfaces which API to enable', () async {
      final service = DirectionsService(
        apiKey: 'k',
        client: MockClient(
          (_) async => http.Response(
            '{"error":{"message":"Routes API has not been used"}}',
            403,
          ),
        ),
      );
      await expectLater(
        service.fetchRoute(origin: _a, destination: _b),
        throwsA(
          isA<DirectionsException>().having(
            (e) => e.message,
            'message',
            contains('not enabled'),
          ),
        ),
      );
    });

    test('TrafficRouteService works with only the manifest key', () async {
      _mockIdentity({'key': 'k', 'package': 'com.x', 'sha1': 'AB12'});
      final service = TrafficRouteService(
        auth: GoogleApiAuth(apiKey: '', isAndroid: true),
        client: MockClient((_) async => http.Response(routesBody, 200)),
      );
      final route = await service.fetch(
        origin: const GeoCoord(12.97, 77.59),
        destination: const GeoCoord(12.98, 77.6),
      );
      expect(route.source, isNot(SimRouteSource.straightLine));
      expect(route.warning, isNull);
    });

    test('PlaceSearchService falls back to Geocoding', () async {
      final service = PlaceSearchService(
        apiKey: 'k',
        client: MockClient((req) async {
          if (req.url.host == 'places.googleapis.com') {
            return http.Response('{"error":{"message":"disabled"}}', 403);
          }
          return http.Response(
            jsonEncode({
              'status': 'OK',
              'results': [
                {
                  'formatted_address': 'Cubbon Park, Bengaluru',
                  'geometry': {
                    'location': {'lat': 12.97, 'lng': 77.59},
                  },
                },
              ],
            }),
            200,
          );
        }),
      );
      final results = await service.search('cubbon');
      expect(results.single.name, 'Cubbon Park');
      expect(results.single.point, const GeoPoint(12.97, 77.59));
    });

    test('PlaceSearchService reports the Places error if both fail', () async {
      final service = PlaceSearchService(
        apiKey: 'k',
        client: MockClient((_) async => http.Response('{}', 403)),
      );
      await expectLater(
        service.search('x'),
        throwsA(isA<PlaceSearchException>()),
      );
    });
  });

  test('GeoShare keeps the transport mode and still reads old payloads', () {
    final share = const GeoShare.route(
      origin: _a,
      destination: _b,
      mode: 'cycle',
      path: [_a, _b],
    );
    expect(GeoShare.tryDecode(share.encode())!.mode, 'cycle');
    final legacy = jsonEncode({
      'k': 'route',
      'p': [1.0, 2.0],
      'd': [3.0, 4.0],
    });
    expect(GeoShare.tryDecode(legacy)!.mode, isNull);
  });

  test('parseCoordinateQuery understands lat, lng input', () {
    expect(parseCoordinateQuery('12.97, 77.59'), const GeoCoord(12.97, 77.59));
    expect(parseCoordinateQuery('-33.9 151.2'), const GeoCoord(-33.9, 151.2));
    expect(parseCoordinateQuery('Bangalore'), isNull);
    expect(parseCoordinateQuery('95, 10'), isNull);
  });

  group('PlaceSearchField', () {
    testWidgets('searches, lists results and reports the choice', (
      tester,
    ) async {
      PlaceHit? chosen;
      final queries = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceSearchField(
              label: 'Start',
              search: (q) async {
                queries.add(q);
                return const [
                  PlaceHit(
                    name: 'Cubbon Park',
                    address: 'Bengaluru',
                    coord: GeoCoord(12.97, 77.59),
                  ),
                ];
              },
              onSelected: (hit) => chosen = hit,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'cubbon');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(queries, ['cubbon']);

      await tester.tap(find.text('Cubbon Park'));
      await tester.pumpAndSettle();
      expect(chosen?.coord, const GeoCoord(12.97, 77.59));
      expect(find.text('Bengaluru'), findsNothing);
    });

    testWidgets('shows the search error', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PlaceSearchField(
              search: (_) async => throw PlaceSearchException('No key'),
              onSelected: (_) {},
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'abc');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('No key'), findsOneWidget);
    });
  });
}
