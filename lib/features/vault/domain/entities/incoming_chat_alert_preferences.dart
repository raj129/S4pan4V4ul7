import 'package:equatable/equatable.dart';

enum NotificationAlertSource { system, custom }

enum IncomingChatVibrationPattern { standard, shortPulses, longPulses }

class IncomingChatAlertPreferences extends Equatable {
  const IncomingChatAlertPreferences({
    this.source = NotificationAlertSource.system,
    this.ringSoundEnabled = true,
    this.vibrationEnabled = true,
    this.vibrationPattern = IncomingChatVibrationPattern.standard,
    this.notificationSoundUri,
    this.flashlightEnabled = false,
  });

  final NotificationAlertSource source;
  final bool ringSoundEnabled;
  final bool vibrationEnabled;
  final IncomingChatVibrationPattern vibrationPattern;
  final String? notificationSoundUri;
  final bool flashlightEnabled;

  IncomingChatAlertPreferences copyWith({
    NotificationAlertSource? source,
    bool? ringSoundEnabled,
    bool? vibrationEnabled,
    IncomingChatVibrationPattern? vibrationPattern,
    String? notificationSoundUri,
    bool clearNotificationSoundUri = false,
    bool? flashlightEnabled,
  }) => IncomingChatAlertPreferences(
    source: source ?? this.source,
    ringSoundEnabled: ringSoundEnabled ?? this.ringSoundEnabled,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    vibrationPattern: vibrationPattern ?? this.vibrationPattern,
    notificationSoundUri: clearNotificationSoundUri
        ? null
        : notificationSoundUri ?? this.notificationSoundUri,
    flashlightEnabled: flashlightEnabled ?? this.flashlightEnabled,
  );

  Map<String, Object?> toJson() => {
    'source': source.name,
    'ringSoundEnabled': ringSoundEnabled,
    'vibrationEnabled': vibrationEnabled,
    'vibrationPattern': vibrationPattern.name,
    if (notificationSoundUri != null)
      'notificationSoundUri': notificationSoundUri,
    'flashlightEnabled': flashlightEnabled,
  };

  factory IncomingChatAlertPreferences.fromJson(Object? raw) {
    if (raw is! Map) return const IncomingChatAlertPreferences();
    final ringSoundEnabled = raw['ringSoundEnabled'];
    final vibrationEnabled = raw['vibrationEnabled'];
    final vibrationPatternName = raw['vibrationPattern'];
    final notificationSoundUri =
        raw['notificationSoundUri'] ?? raw['ringtoneUri'];
    final flashlightEnabled = raw['flashlightEnabled'];
    return IncomingChatAlertPreferences(
      source: raw['source'] == NotificationAlertSource.custom.name
          ? NotificationAlertSource.custom
          : NotificationAlertSource.system,
      ringSoundEnabled: ringSoundEnabled is bool ? ringSoundEnabled : true,
      vibrationEnabled: vibrationEnabled is bool ? vibrationEnabled : true,
      vibrationPattern: IncomingChatVibrationPattern.values.firstWhere(
        (pattern) => pattern.name == vibrationPatternName,
        orElse: () => IncomingChatVibrationPattern.standard,
      ),
      notificationSoundUri: notificationSoundUri is String
          ? notificationSoundUri
          : null,
      flashlightEnabled: flashlightEnabled is bool ? flashlightEnabled : false,
    );
  }

  @override
  List<Object?> get props => [
    source,
    ringSoundEnabled,
    vibrationEnabled,
    vibrationPattern,
    notificationSoundUri,
    flashlightEnabled,
  ];
}
