import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'geo_share.dart';

/// A named place the user keeps for sending on demand or arrival alerts.
class SavedPlace extends Equatable {
  const SavedPlace({
    required this.id,
    required this.ownerUid,
    required this.label,
    required this.point,
  });

  final String id;
  final String ownerUid;
  final String label;
  final GeoPoint point;

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': ownerUid,
    'label': label,
    'p': point.toJson(),
  };

  static SavedPlace? fromJson(Map<String, dynamic> json) {
    final point = GeoPoint.fromJson(json['p']);
    final id = json['id'] as String?;
    final owner = json['owner'] as String?;
    if (point == null || id == null || owner == null) return null;
    return SavedPlace(
      id: id,
      ownerUid: owner,
      label: json['label'] as String? ?? '',
      point: point,
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
  List<Object?> get props => [id, ownerUid, label, point];
}
