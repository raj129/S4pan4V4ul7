import 'dart:io';

import 'package:flutter/services.dart';

/// What the installed Android build presents to Google Maps, plus native
/// metadata fallback for API keys defined in `.api_keys.json`.
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

  static String? _cachedGiphyKey;

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

  /// Reads the GIPHY API key baked into `AndroidManifest.xml` from `.api_keys.json`
  /// when `--dart-define` was not passed at launch.
  static Future<String> loadGiphyApiKey() async {
    if (_cachedGiphyKey != null) return _cachedGiphyKey!;
    if (!Platform.isAndroid) return '';
    try {
      final value = await _channel.invokeMethod<String>('getGiphyApiKey');
      final trimmed = (value ?? '').trim();
      if (trimmed.isNotEmpty) {
        _cachedGiphyKey = trimmed;
      }
      return trimmed;
    } on PlatformException {
      return '';
    } on MissingPluginException {
      return '';
    }
  }

  /// Toggles map-surface compatibility mode on Android so the Google Maps
  /// platform view is not blanked by `FLAG_SECURE` while on screen.
  static Future<void> setMapActive(bool active) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('setMapActive', {'active': active});
    } on PlatformException {
      // Ignore on unsupported environments.
    } on MissingPluginException {
      // Ignore in widget tests.
    }
  }
}
