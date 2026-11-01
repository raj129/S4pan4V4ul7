import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../geo_fix.dart';

/// Whether this app can push locations to Android's test providers.
enum SystemMockAvailability {
  /// Not Android, or the native plugin is missing.
  unsupported,

  /// Android, but this app isn't chosen in Developer options →
  /// "Select mock location app".
  notSelected,
  ready,
}

/// Talks to the native `MockLocationPlugin`, which feeds the OS location
/// providers so every app on the device sees the mocked position.
class SystemMockBridge {
  SystemMockBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.system.calculator/mock_location';

  final MethodChannel _channel;

  bool get isSupportedPlatform => Platform.isAndroid;

  /// Called when the user taps "Stop" on the ongoing notification.
  set onStopRequested(void Function()? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'stopRequested') handler();
            },
    );
  }

  Future<SystemMockAvailability> availability() async {
    if (!isSupportedPlatform) return SystemMockAvailability.unsupported;
    try {
      final selected = await _channel.invokeMethod<bool>('isMockAppSelected');
      return selected == true
          ? SystemMockAvailability.ready
          : SystemMockAvailability.notSelected;
    } on MissingPluginException {
      return SystemMockAvailability.unsupported;
    } on PlatformException {
      return SystemMockAvailability.notSelected;
    }
  }

  Future<void> openDeveloperSettings() async {
    if (!isSupportedPlatform) return;
    await _channel.invokeMethod<void>('openDeveloperSettings');
  }

  /// Starts the foreground service and registers the test providers.
  /// Throws [PlatformException] (code `not_selected`) when not permitted.
  Future<void> start({required String status}) =>
      _channel.invokeMethod<void>('start', {'status': status});

  Future<void> push(GeoFix fix, {String? status}) =>
      _channel.invokeMethod<void>('push', {
        'lat': fix.latitude,
        'lng': fix.longitude,
        'acc': fix.accuracy,
        'alt': fix.altitude,
        'bearing': fix.heading,
        'speed': fix.speed,
        'status': ?status,
      });

  Future<void> stop() async {
    if (!isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // Nothing to stop.
    }
  }
}
