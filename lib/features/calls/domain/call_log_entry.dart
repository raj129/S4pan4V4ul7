import 'package:equatable/equatable.dart';

/// Matches `CallLog.Calls` type constants on Android.
enum CallLogType {
  incoming(1),
  outgoing(2),
  missed(3);

  const CallLogType(this.platformValue);

  final int platformValue;

  static CallLogType? fromPlatform(int value) {
    for (final type in values) {
      if (type.platformValue == value) return type;
    }
    return null;
  }
}

class CallLogEntry extends Equatable {
  const CallLogEntry({
    required this.id,
    required this.number,
    required this.type,
    required this.timestamp,
    this.name,
    this.durationSeconds = 0,
  });

  final String id;
  final String number;
  final String? name;
  final CallLogType type;
  final DateTime timestamp;
  final int durationSeconds;

  @override
  List<Object?> get props => [
    id,
    number,
    name,
    type,
    timestamp,
    durationSeconds,
  ];
}
