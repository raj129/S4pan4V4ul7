import 'dart:io' show Platform;

import 'package:flutter/services.dart';

abstract interface class ScreenshotProtectionController {
  bool get isSupportedPlatform;

  Future<void> setEnabled(bool enabled);
}

class AndroidScreenshotProtection implements ScreenshotProtectionController {
  const AndroidScreenshotProtection({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.system.calculator/screenshot_protection';

  final MethodChannel _channel;

  @override
  bool get isSupportedPlatform => Platform.isAndroid;

  @override
  Future<void> setEnabled(bool enabled) async {
    if (!isSupportedPlatform) return;
    await _channel.invokeMethod<void>('setEnabled', {'enabled': enabled});
  }
}
