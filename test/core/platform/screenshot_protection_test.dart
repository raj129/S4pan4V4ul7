import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/platform/screenshot_protection.dart';

class _AndroidScreenshotProtection extends AndroidScreenshotProtection {
  const _AndroidScreenshotProtection({required super.channel});

  @override
  bool get isSupportedPlatform => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forwards the screenshot protection preference to Android', () async {
    const channel = MethodChannel(AndroidScreenshotProtection.channelName);
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    const protection = _AndroidScreenshotProtection(channel: channel);
    await protection.setEnabled(false);

    expect(calls, hasLength(1));
    expect(calls.single.method, 'setEnabled');
    expect(calls.single.arguments, {'enabled': false});
  });
}
