import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/core/media/animated_media.dart';
import 'package:photo_vault/core/widgets/inline_media_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MediaAnimationPreference.instance.resetForTesting();
  });

  testWidgets(
    'Motion Photo falls back to its still image without native video',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        final stillBytes = Uint8List.fromList(
          img.encodePng(img.Image(width: 4, height: 4)),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 240,
              height: 240,
              child: InlineMotionPhotoPreview(
                videoBytes: Uint8List.fromList([1, 2, 3]),
                stillBytes: stillBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(Image), findsOneWidget);
        expect(find.byType(AndroidView), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );

  testWidgets(
    'Hitting pause returns to steady still image',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final previousPlatform = debugDefaultTargetPlatformOverride;
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      for (var id = 0; id < 10; id++) {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          MethodChannel('photo_vault/inline_media/$id'),
          (call) async {
            if (call.method == 'getStatus') {
              return {'status': 'ready', 'playing': true};
            }
            return null;
          },
        );
      }

      try {
        final stillBytes = Uint8List.fromList(
          img.encodePng(img.Image(width: 4, height: 4)),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: 240,
              height: 240,
              child: InlineMotionPhotoPreview(
                videoBytes: Uint8List.fromList([1, 2, 3]),
                stillBytes: stillBytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // While playing, pause button is present
        final pauseButton = find.byTooltip('Pause motion photo');
        expect(pauseButton, findsOneWidget);

        // Tap pause
        await tester.tap(pauseButton);
        await tester.pumpAndSettle();

        // It should have returned to steady still image (play button now shown, no AndroidView)
        expect(find.byTooltip('Play motion photo'), findsOneWidget);
        expect(find.byType(AndroidView), findsNothing);

        // Set mock for view 1 for when play is pressed again
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('photo_vault/inline_media/1'),
          (call) async {
            if (call.method == 'getStatus') {
              return {'status': 'ready', 'playing': true};
            }
            return null;
          },
        );

        // Tap play again
        await tester.tap(find.byTooltip('Play motion photo'));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Pause motion photo'), findsOneWidget);
        expect(find.byType(AndroidView), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('photo_vault/inline_media/0'),
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('photo_vault/inline_media/1'),
          null,
        );
        debugDefaultTargetPlatformOverride = previousPlatform;
      }
    },
  );
}
