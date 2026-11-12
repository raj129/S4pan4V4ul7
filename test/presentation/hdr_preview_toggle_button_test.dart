import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/media/animated_media.dart';
import 'package:photo_vault/core/platform/hdr_preview_capability.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/core/widgets/hdr_preview_toggle_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('photo_vault/hdr_preview');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final capability = HdrPreviewCapability.instance;
  final preference = HdrPreviewPreference.instance;
  TargetPlatform? previousPlatform;

  setUp(() {
    previousPlatform = debugDefaultTargetPlatformOverride;
    capability.resetForTesting();
    preference.resetForTesting();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    capability.resetForTesting();
    preference.resetForTesting();
    debugDefaultTargetPlatformOverride = previousPlatform;
  });

  testWidgets('hides the toggle when HDR rendering is unavailable', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: AppBar(actions: [HdrPreviewToggleButton()])),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('HDR preview on; tap to turn off'), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });

  testWidgets('one global toggle persists and shows HDR off state', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final settings = InMemorySettingsRepository();
    preference.configure(settings);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'isSupported');
      return true;
    });

    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: AppBar(actions: [HdrPreviewToggleButton()])),
        ),
      );
      await tester.pumpAndSettle();

      final toggle = find.byTooltip('HDR preview on; tap to turn off');
      expect(toggle, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(find.byTooltip('HDR preview off; tap to turn on'), findsOneWidget);
      expect(find.byIcon(Icons.hdr_off_rounded), findsOneWidget);
      expect(preference.enabled.value, isFalse);
      expect(await settings.isHdrPhotoPreviewEnabled(), isFalse);
    } finally {
      debugDefaultTargetPlatformOverride = previousPlatform;
    }
  });
}
