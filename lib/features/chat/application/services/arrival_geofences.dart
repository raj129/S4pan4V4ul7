import 'package:flutter/services.dart';

/// One arrival place to watch with the OS geofencing service.
class ArrivalFence {
  const ArrivalFence({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
  });

  final String id;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  Map<String, Object> toMap() => {
    'id': id,
    'lat': latitude,
    'lng': longitude,
    'radius': radiusMeters,
  };
}

/// Native geofence registration. Android only.
abstract interface class ArrivalGeofences {
  /// Replaces every registered fence with [fences]. Empty clears them all.
  Future<void> sync(List<ArrivalFence> fences);

  /// Enter events still queued natively. Stays queued until [ackPending].
  Future<List<ArrivalGeofenceEvent>> peekPending();

  /// Removes events once they are handled, so a failed send is retried.
  Future<void> ackPending(List<String> eids);
}

/// One geofence enter. [latitude]/[longitude] is where the device was when
/// the OS reported it, when the OS provided it.
class ArrivalGeofenceEvent {
  const ArrivalGeofenceEvent({
    required this.eid,
    required this.alertId,
    required this.enqueuedAt,
    this.latitude,
    this.longitude,
  });

  /// Queue entry id, unique per enter event.
  final String eid;
  final String alertId;
  final DateTime enqueuedAt;
  final double? latitude;
  final double? longitude;
}

class ChannelArrivalGeofences implements ArrivalGeofences {
  ChannelArrivalGeofences({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'photo_vault/arrival_geofence';

  final MethodChannel _channel;

  @override
  Future<void> sync(List<ArrivalFence> fences) => _channel.invokeMethod<void>(
    'sync',
    {'fences': [for (final f in fences) f.toMap()]},
  );

  @override
  Future<List<ArrivalGeofenceEvent>> peekPending() async {
    final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
      'peekPending',
    );
    return [
      for (final item in raw ?? const <Map<Object?, Object?>>[])
        if (item['eid'] is String && item['id'] is String)
          ArrivalGeofenceEvent(
            eid: item['eid']! as String,
            alertId: item['id']! as String,
            enqueuedAt: DateTime.fromMillisecondsSinceEpoch(
              (item['ts'] as num?)?.toInt() ?? 0,
            ),
            latitude: (item['lat'] as num?)?.toDouble(),
            longitude: (item['lng'] as num?)?.toDouble(),
          ),
    ];
  }

  @override
  Future<void> ackPending(List<String> eids) =>
      _channel.invokeMethod<void>('ackPending', {'eids': eids});
}
