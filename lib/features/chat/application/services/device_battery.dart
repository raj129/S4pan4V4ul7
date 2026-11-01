import 'package:flutter/services.dart';

/// Battery level (0-100) and whether the device is on power.
class BatteryStatus {
  const BatteryStatus({required this.level, required this.charging});

  final int level;
  final bool charging;
}

/// Reads the device battery. Android only.
abstract interface class BatteryReader {
  Future<BatteryStatus?> read();
}

class ChannelBatteryReader implements BatteryReader {
  ChannelBatteryReader({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'photo_vault/battery';

  final MethodChannel _channel;

  @override
  Future<BatteryStatus?> read() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('status');
      if (raw == null) return null;
      final level = raw['level'];
      if (level is! int || level < 0) return null;
      return BatteryStatus(
        level: level,
        charging: raw['charging'] as bool? ?? false,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
