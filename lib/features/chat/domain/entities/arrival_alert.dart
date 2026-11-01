import 'dart:convert';

import 'package:equatable/equatable.dart';

import 'geo_share.dart';

enum ArrivalAlertStatus { armed, triggered }

/// A place the user wants the chat partner to be told about on arrival.
class ArrivalAlert extends Equatable {
  const ArrivalAlert({
    required this.id,
    required this.ownerUid,
    required this.threadId,
    required this.recipientUid,
    required this.label,
    required this.point,
    this.radiusMeters = defaultRadiusMeters,
    this.status = ArrivalAlertStatus.armed,
    this.placeId,
  });

  static const double defaultRadiusMeters = 100;

  /// Radii offered when saving a place. 100 m is the smallest that Android
  /// geofencing reliably honours.

  final String id;
  final String ownerUid;
  final String threadId;
  final String recipientUid;
  final String label;
  final GeoPoint point;
  final double radiusMeters;
  final ArrivalAlertStatus status;

  /// The saved place this alert was made from, when there is one.
  final String? placeId;

  bool get isArmed => status == ArrivalAlertStatus.armed;

  ArrivalAlert copyWith({ArrivalAlertStatus? status}) => ArrivalAlert(
    id: id,
    ownerUid: ownerUid,
    threadId: threadId,
    recipientUid: recipientUid,
    label: label,
    point: point,
    radiusMeters: radiusMeters,
    status: status ?? this.status,
    placeId: placeId,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'owner': ownerUid,
    'thread': threadId,
    'to': recipientUid,
    'label': label,
    'p': point.toJson(),
    'radius': radiusMeters,
    'status': status.name,
    if (placeId != null) 'pl': placeId,
  };

  static ArrivalAlert? fromJson(Map<String, dynamic> json) {
    final point = GeoPoint.fromJson(json['p']);
    final id = json['id'] as String?;
    final owner = json['owner'] as String?;
    final thread = json['thread'] as String?;
    final to = json['to'] as String?;
    if (point == null ||
        id == null ||
        owner == null ||
        thread == null ||
        to == null) {
      return null;
    }
    return ArrivalAlert(
      id: id,
      ownerUid: owner,
      threadId: thread,
      recipientUid: to,
      label: json['label'] as String? ?? '',
      point: point,
      radiusMeters:
          (json['radius'] as num?)?.toDouble() ?? defaultRadiusMeters,
      status: json['status'] == ArrivalAlertStatus.triggered.name
          ? ArrivalAlertStatus.triggered
          : ArrivalAlertStatus.armed,
      placeId: json['pl'] as String?,
    );
  }

  static String encodeList(List<ArrivalAlert> alerts) =>
      jsonEncode([for (final a in alerts) a.toJson()]);

  static List<ArrivalAlert> decodeList(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final item in list)
          if (item is Map) ?ArrivalAlert.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  List<Object?> get props => [
    id,
    ownerUid,
    threadId,
    recipientUid,
    label,
    point,
    radiusMeters,
    status,
    placeId,
  ];
}
