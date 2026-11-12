import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/platform/hdr_preview_capability.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('photo_vault/hdr_preview');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final capability = HdrPreviewCapability.instance;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    capability.resetForTesting();
    debugDefaultTargetPlatformOverride = null;
  });

  test('HDR is unavailable outside Android', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    capability.resetForTesting();

    expect(await capability.load(), isFalse);
    expect(capability.available.value, isFalse);
  });

  test('HDR availability comes from the native display capability', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isSupported');
      return true;
    });

    expect(await capability.load(), isTrue);
    expect(capability.available.value, isTrue);
  });
}
