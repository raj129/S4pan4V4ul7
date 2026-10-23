import 'dart:io';

import 'package:flutter/services.dart';

/// What the installed Android build presents to Google Maps.
///
/// google_maps_flutter exposes no callback for tile authorization failures, so
/// this reports the inputs Google validates. The authorization result itself
/// is only visible in Logcat ("Google Maps Android API").
class MapsDiagnostics {
  const MapsDiagnostics({
    required this.keyPresent,
    this.packageName,
    this.keyMasked,
    this.signingSha1,
  });

  final bool keyPresent;
  final String? packageName;
  final String? keyMasked;
  final String? signingSha1;

  static const _channel = MethodChannel(
    'com.system.calculator/maps_diagnostics',
  );

  /// Null when the platform cannot report (non-Android, or channel missing).
  static Future<MapsDiagnostics?> load() async {
    if (!Platform.isAndroid) return null;
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('report');
      if (raw == null) return null;
      return MapsDiagnostics(
        keyPresent: raw['keyPresent'] == true,
        packageName: raw['package'] as String?,
        keyMasked: raw['keyMasked'] as String?,
        signingSha1: raw['signingSha1'] as String?,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
