import 'dart:convert';

import 'package:equatable/equatable.dart';

/// A coloured label for a place. Presets are always available; custom tags
/// are created by the user.
class PlaceTag extends Equatable {
  const PlaceTag({required this.name, required this.color});

  final String name;

  /// ARGB colour value.
  final int color;

  static const presets = [
    PlaceTag(name: 'Home', color: 0xFF1E88E5),
    PlaceTag(name: 'Work', color: 0xFFFB8C00),
    PlaceTag(name: 'Campus', color: 0xFF43A047),
    PlaceTag(name: 'Other', color: 0xFF757575),
  ];

  /// Colours offered when the user creates a custom tag.
  static const paletteColors = [
    0xFF8E24AA,
    0xFFE53935,
    0xFF00ACC1,
    0xFFFDD835,
    0xFF6D4C41,
    0xFFD81B60,
  ];

  Map<String, dynamic> toJson() => {'n': name, 'c': color};

  static PlaceTag? fromJson(Map<String, dynamic> json) {
    final name = json['n'] as String?;
    final color = (json['c'] as num?)?.toInt();
    if (name == null || name.trim().isEmpty || color == null) return null;
    return PlaceTag(name: name, color: color);
  }

  static String encodeList(List<PlaceTag> tags) =>
      jsonEncode([for (final t in tags) t.toJson()]);

  static List<PlaceTag> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) ?PlaceTag.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  List<Object?> get props => [name, color];
}
