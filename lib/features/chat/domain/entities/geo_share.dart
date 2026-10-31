import 'dart:convert';

import 'package:equatable/equatable.dart';

enum GeoShareKind { pin, route, arrival }

/// A latitude/longitude pair used by shared pins, routes and arrival alerts.
class GeoPoint extends Equatable {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  List<double> toJson() => [latitude, longitude];

  static GeoPoint? fromJson(Object? json) {
    if (json is! List || json.length != 2) return null;
    final lat = json[0];
    final lng = json[1];
    if (lat is! num || lng is! num) return null;
    return GeoPoint(lat.toDouble(), lng.toDouble());
  }

  @override
  List<Object?> get props => [latitude, longitude];
}

/// Payload of a pin, route or arrival chat message.
///
/// It is serialised to JSON and sent as the encrypted message body, so no
/// coordinates are ever stored in clear text.
class GeoShare extends Equatable {
  const GeoShare({
    required this.kind,
    required this.point,
    this.label = '',
    this.destination,
    this.path = const [],
    this.distanceMeters,
    this.durationSeconds,
  });

  const GeoShare.pin({required GeoPoint point, String label = ''})
    : this(kind: GeoShareKind.pin, point: point, label: label);

  const GeoShare.arrival({required GeoPoint point, required String label})
    : this(kind: GeoShareKind.arrival, point: point, label: label);

  const GeoShare.route({
    required GeoPoint origin,
    required GeoPoint destination,
    String label = '',
    List<GeoPoint> path = const [],
    double? distanceMeters,
    int? durationSeconds,
  }) : this(
         kind: GeoShareKind.route,
         point: origin,
         label: label,
         destination: destination,
         path: path,
         distanceMeters: distanceMeters,
         durationSeconds: durationSeconds,
       );

  final GeoShareKind kind;

  /// The pin, the arrival place, or the route origin.
  final GeoPoint point;
  final String label;
  final GeoPoint? destination;
  final List<GeoPoint> path;
  final double? distanceMeters;
  final int? durationSeconds;

  bool get isRoute => kind == GeoShareKind.route && destination != null;

  /// Short text used for thread-list previews and reply quotes.
  String get preview => switch (kind) {
    GeoShareKind.pin => label.isEmpty ? '📍 Pin' : '📍 $label',
    GeoShareKind.route => label.isEmpty ? '🧭 Route' : '🧭 $label',
    GeoShareKind.arrival =>
      label.isEmpty ? '✅ I have arrived' : '✅ I have reached $label',
  };

  String encode() => jsonEncode({
    'k': kind.name,
    'p': point.toJson(),
    if (label.isNotEmpty) 'l': label,
    if (destination != null) 'd': destination!.toJson(),
    if (path.isNotEmpty) 'r': [for (final p in path) p.toJson()],
    if (distanceMeters != null) 'm': distanceMeters,
    if (durationSeconds != null) 's': durationSeconds,
  });

  /// Returns null when [text] is not a valid geo payload.
  static GeoShare? tryDecode(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final json = jsonDecode(text);
      if (json is! Map) return null;
      final kindName = json['k'];
      GeoShareKind? kind;
      for (final k in GeoShareKind.values) {
        if (k.name == kindName) kind = k;
      }
      final point = GeoPoint.fromJson(json['p']);
      if (kind == null || point == null) return null;
      return GeoShare(
        kind: kind,
        point: point,
        label: json['l'] as String? ?? '',
        destination: GeoPoint.fromJson(json['d']),
        path: [
          for (final raw in (json['r'] as List? ?? const []))
            ?GeoPoint.fromJson(raw),
        ],
        distanceMeters: (json['m'] as num?)?.toDouble(),
        durationSeconds: (json['s'] as num?)?.toInt(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  List<Object?> get props => [
    kind,
    point,
    label,
    destination,
    path,
    distanceMeters,
    durationSeconds,
  ];
}
