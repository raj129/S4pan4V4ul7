import 'package:equatable/equatable.dart';

/// Represents a single GPS coordinate reading for live location sharing.
class LiveLocationPoint extends Equatable {
  const LiveLocationPoint({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    required this.timestamp,
    this.heading,
    this.speed,
    this.batteryLevel,
    this.charging,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final double? heading;
  final double? speed;
  final DateTime timestamp;

  /// Sharer's battery percentage (0-100), when known.
  final int? batteryLevel;
  final bool? charging;

  LiveLocationPoint withBattery({required int level, required bool charging}) =>
      LiveLocationPoint(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        timestamp: timestamp,
        heading: heading,
        speed: speed,
        batteryLevel: level,
        charging: charging,
      );

  Map<String, dynamic> toJson() => {
    'lat': latitude,
    'lng': longitude,
    'acc': accuracy,
    if (heading != null) 'hdg': heading,
    if (speed != null) 'spd': speed,
    if (batteryLevel != null) 'bat': batteryLevel,
    if (charging != null) 'chg': charging,
    'ts': timestamp.millisecondsSinceEpoch,
  };

  factory LiveLocationPoint.fromJson(Map<String, dynamic> json) {
    return LiveLocationPoint(
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lng'] as num).toDouble(),
      accuracy: (json['acc'] as num).toDouble(),
      heading: (json['hdg'] as num?)?.toDouble(),
      speed: (json['spd'] as num?)?.toDouble(),
      batteryLevel: (json['bat'] as num?)?.toInt(),
      charging: json['chg'] as bool?,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        json['ts'] as int,
        isUtc: true,
      ),
    );
  }

  @override
  List<Object?> get props => [
    latitude,
    longitude,
    accuracy,
    heading,
    speed,
    timestamp,
    batteryLevel,
    charging,
  ];
}

/// Represents the active state and latest location of a user sharing live location in a thread.
class LiveLocationSession extends Equatable {
  const LiveLocationSession({
    required this.sessionId,
    required this.threadId,
    required this.userId,
    required this.isActive,
    required this.startedAt,
    required this.expiresAt,
    required this.lastUpdatedAt,
    this.currentPoint,
    this.stoppedAt,
  });

  final String sessionId;
  final String threadId;
  final String userId;
  final bool isActive;
  final DateTime startedAt;
  final DateTime expiresAt;
  final DateTime lastUpdatedAt;
  final LiveLocationPoint? currentPoint;
  final DateTime? stoppedAt;

  /// True if the session duration has passed.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// True if no location updates have arrived within 90 seconds.
  bool get isStale => DateTime.now().difference(lastUpdatedAt).inSeconds > 90;

  /// True if the session is currently active, unexpired, and fresh.
  bool get isLive => isActive && !isExpired && !isStale;

  LiveLocationSession copyWith({
    String? sessionId,
    String? threadId,
    String? userId,
    bool? isActive,
    DateTime? startedAt,
    DateTime? expiresAt,
    DateTime? lastUpdatedAt,
    LiveLocationPoint? currentPoint,
    DateTime? stoppedAt,
  }) {
    return LiveLocationSession(
      sessionId: sessionId ?? this.sessionId,
      threadId: threadId ?? this.threadId,
      userId: userId ?? this.userId,
      isActive: isActive ?? this.isActive,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      lastUpdatedAt: lastUpdatedAt ?? this.lastUpdatedAt,
      currentPoint: currentPoint ?? this.currentPoint,
      stoppedAt: stoppedAt ?? this.stoppedAt,
    );
  }

  @override
  List<Object?> get props => [
    sessionId,
    threadId,
    userId,
    isActive,
    startedAt,
    expiresAt,
    lastUpdatedAt,
    currentPoint,
    stoppedAt,
  ];
}
