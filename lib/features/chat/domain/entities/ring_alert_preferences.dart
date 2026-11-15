import 'package:equatable/equatable.dart';

enum RingAlertSource { system, custom }

enum RingAlertMode { ringAndVibrate, ringtone, vibrate, silent }

enum RingVibrationPattern { standard, shortPulses, longPulses }

enum RingFlashPattern { slowBlink, doubleBlink, fastBlink }

class RingAlertPreferences extends Equatable {
  const RingAlertPreferences({
    this.enabled = true,
    this.source = RingAlertSource.system,
    this.ringSoundEnabled = true,
    this.vibrationEnabled = true,
    this.ringtoneUri,
    this.timeoutSeconds = defaultTimeoutSeconds,
    this.vibrationPattern = RingVibrationPattern.standard,
    this.flashlightEnabled = false,
    this.flashPattern = RingFlashPattern.slowBlink,
    this.testDelaySeconds = defaultTestDelaySeconds,
  });

  static const defaultTimeoutSeconds = 5;
  static const timeoutOptionsSeconds = [5, 10, 15, 30, 45, 60, 90, 120];
  static const defaultTestDelaySeconds = 0;
  static const testDelayOptionsSeconds = [0, 3, 5, 10, 15];

  final bool enabled;
  final RingAlertSource source;
  final bool ringSoundEnabled;
  final bool vibrationEnabled;
  final String? ringtoneUri;
  final int timeoutSeconds;
  final RingVibrationPattern vibrationPattern;
  final bool flashlightEnabled;
  final RingFlashPattern flashPattern;
  final int testDelaySeconds;

  RingAlertMode get mode => switch ((ringSoundEnabled, vibrationEnabled)) {
    (true, true) => RingAlertMode.ringAndVibrate,
    (true, false) => RingAlertMode.ringtone,
    (false, true) => RingAlertMode.vibrate,
    (false, false) => RingAlertMode.silent,
  };

  RingAlertPreferences copyWith({
    bool? enabled,
    RingAlertSource? source,
    bool? ringSoundEnabled,
    bool? vibrationEnabled,
    String? ringtoneUri,
    bool clearRingtoneUri = false,
    int? timeoutSeconds,
    RingVibrationPattern? vibrationPattern,
    bool? flashlightEnabled,
    RingFlashPattern? flashPattern,
    int? testDelaySeconds,
  }) => RingAlertPreferences(
    enabled: enabled ?? this.enabled,
    source: source ?? this.source,
    ringSoundEnabled: ringSoundEnabled ?? this.ringSoundEnabled,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
    ringtoneUri: clearRingtoneUri ? null : ringtoneUri ?? this.ringtoneUri,
    timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    vibrationPattern: vibrationPattern ?? this.vibrationPattern,
    flashlightEnabled: flashlightEnabled ?? this.flashlightEnabled,
    flashPattern: flashPattern ?? this.flashPattern,
    testDelaySeconds: testDelaySeconds ?? this.testDelaySeconds,
  );

  Map<String, Object?> toFirestore() => {
    'enabled': enabled,
    'source': source.name,
    'mode': mode.name,
    'ringSoundEnabled': ringSoundEnabled,
    'vibrationEnabled': vibrationEnabled,
    if (ringtoneUri != null) 'ringtoneUri': ringtoneUri,
    'timeoutSeconds': timeoutSeconds,
    'vibrationPattern': vibrationPattern.name,
    'flashlightEnabled': flashlightEnabled,
    'flashPattern': flashPattern.name,
    'testDelaySeconds': testDelaySeconds,
  };

  factory RingAlertPreferences.fromFirestore(Map<String, dynamic>? data) {
    final sourceName = data?['source'] as String?;
    final source = RingAlertSource.values.firstWhere(
      (candidate) => candidate.name == sourceName,
      orElse: () => data?.containsKey('mode') == true
          ? RingAlertSource.custom
          : RingAlertSource.system,
    );
    final modeName = data?['mode'] as String?;
    final mode = switch (modeName) {
      'ringAndVibrate' => RingAlertMode.ringAndVibrate,
      'ringtone' => RingAlertMode.ringtone,
      'vibrate' => RingAlertMode.vibrate,
      'silent' => RingAlertMode.silent,
      _ => RingAlertMode.ringAndVibrate,
    };
    final oldRingSoundEnabled =
        mode == RingAlertMode.ringAndVibrate || mode == RingAlertMode.ringtone;
    final oldVibrationEnabled =
        mode == RingAlertMode.ringAndVibrate || mode == RingAlertMode.vibrate;
    final vibrationPatternName = data?['vibrationPattern'] as String?;
    final vibrationPattern = RingVibrationPattern.values.firstWhere(
      (candidate) => candidate.name == vibrationPatternName,
      orElse: () => RingVibrationPattern.standard,
    );
    final flashPatternName = data?['flashPattern'] as String?;
    final flashPattern = RingFlashPattern.values.firstWhere(
      (candidate) => candidate.name == flashPatternName,
      orElse: () => RingFlashPattern.slowBlink,
    );
    final timeout = (data?['timeoutSeconds'] as num?)?.toInt();
    final testDelay = (data?['testDelaySeconds'] as num?)?.toInt();
    return RingAlertPreferences(
      enabled: data?['enabled'] as bool? ?? true,
      source: source,
      ringSoundEnabled:
          data?['ringSoundEnabled'] as bool? ?? oldRingSoundEnabled,
      vibrationEnabled:
          data?['vibrationEnabled'] as bool? ?? oldVibrationEnabled,
      ringtoneUri: data?['ringtoneUri'] as String?,
      timeoutSeconds: timeoutOptionsSeconds.contains(timeout)
          ? timeout!
          : defaultTimeoutSeconds,
      vibrationPattern: vibrationPattern,
      flashlightEnabled: data?['flashlightEnabled'] as bool? ?? false,
      flashPattern: flashPattern,
      testDelaySeconds: testDelayOptionsSeconds.contains(testDelay)
          ? testDelay!
          : defaultTestDelaySeconds,
    );
  }

  @override
  List<Object?> get props => [
    enabled,
    source,
    ringSoundEnabled,
    vibrationEnabled,
    ringtoneUri,
    timeoutSeconds,
    vibrationPattern,
    flashlightEnabled,
    flashPattern,
    testDelaySeconds,
  ];
}
