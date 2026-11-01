import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'geo_share.dart';

/// A named place the user keeps for sending on demand or arrival alerts.
///
/// Places made from the arrival option are [temporary]: they expire after
/// [temporaryLifetime] unless the user chose to keep them.
class SavedPlace extends Equatable {
  const SavedPlace({
    required this.id,
    required this.ownerUid,
    required this.label,
    required this.point,
    this.radiusMeters = defaultRadiusMeters,
    this.tagName,
    this.tagColor,
    this.temporary = false,
    this.visitCount = 0,
    this.expiresAt,
  });

  static const double defaultRadiusMeters = 100;
  static const Duration temporaryLifetime = Duration(hours: 24);

  final String id;
  final String ownerUid;
  final String label;
  final GeoPoint point;

  /// Arrival radius for this place, set by the user.
  final double radiusMeters;

  /// Tag name such as Home or Campus, and its colour as an ARGB value.
  final String? tagName;
  final int? tagColor;

  final bool temporary;

  /// Number of geofence entries, used to list frequently visited places first.
  final int visitCount;

  /// When a temporary place stops being kept. Null for saved places.
  final DateTime? expiresAt;

  bool isExpired(DateTime now) =>
      temporary && expiresAt != null && now.isAfter(expiresAt!);

  SavedPlace copyWith({
    String? label,
    GeoPoint? point,
    double? radiusMeters,
    String? tagName,
    int? tagColor,
    bool clearTag = false,
    bool? temporary,
    int? visitCount,
    DateTime? expiresAt,
    bool clearExpiry = false,
  }) => SavedPlace(
    id: id,
    ownerUid: ownerUid,
    label: label ?? this.label,
    point: point ?? this.point,
    radiusMeters: radiusMeters ?? this.radiusMeters,
    tagName: clearTag ? null : (tagName ?? this.tagName),
    tagColor: clearTag ? null : (tagColor ?? this.tagColor),
    temporary: temporary ?? this.temporary,
    visitCount: visitCount ?? this.visitCount,
    expiresAt: clearExpiry ? null : (expiresAt ?? this.expiresAt),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': ownerUid,
    'label': label,
    'p': point.toJson(),
    'r': radiusMeters,
    if (tagName != null) 'tg': tagName,
    if (tagColor != null) 'tc': tagColor,
    if (temporary) 'tmp': true,
    'vc': visitCount,
    if (expiresAt != null) 'exp': expiresAt!.millisecondsSinceEpoch,
  };

  static SavedPlace? fromJson(Map<String, dynamic> json) {
    final point = GeoPoint.fromJson(json['p']);
    final id = json['id'] as String?;
    final owner = json['owner'] as String?;
    if (point == null || id == null || owner == null) return null;
    final expires = (json['exp'] as num?)?.toInt();
    return SavedPlace(
      id: id,
      ownerUid: owner,
      label: json['label'] as String? ?? '',
      point: point,
      radiusMeters:
          (json['r'] as num?)?.toDouble() ?? defaultRadiusMeters,
      tagName: json['tg'] as String?,
      tagColor: (json['tc'] as num?)?.toInt(),
      temporary: json['tmp'] as bool? ?? false,
      visitCount: (json['vc'] as num?)?.toInt() ?? 0,
      expiresAt: expires == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expires, isUtc: true),
    );
  }

  static String encodeList(List<SavedPlace> places) =>
      jsonEncode([for (final p in places) p.toJson()]);

  static List<SavedPlace> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) ?SavedPlace.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  List<Object?> get props => [
    id,
    ownerUid,
    label,
    point,
    radiusMeters,
    tagName,
    tagColor,
    temporary,
    visitCount,
    expiresAt,
  ];
}
