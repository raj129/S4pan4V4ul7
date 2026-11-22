import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/core/media/animated_media.dart';
import 'package:photo_vault/core/widgets/animated_media_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Uint8List _twoFrameGif() {
  final frame1 = img.Image(width: 2, height: 2, frameDuration: 40);
  img.fill(frame1, color: img.ColorRgb8(255, 0, 0));
  final frame2 = img.Image(width: 2, height: 2, frameDuration: 40);
  img.fill(frame2, color: img.ColorRgb8(0, 0, 255));
  frame1.addFrame(frame2);
  return Uint8List.fromList(img.encodeGif(frame1));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  testWidgets('tile built after the once-mode preference loaded still renders', (
    tester,
  ) async {
    await MediaAnimationPreference.instance.setMode(MediaAnimationMode.once);
    addTearDown(
      () => MediaAnimationPreference.instance.setMode(MediaAnimationMode.loop),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedMediaImage(
            bytes: Uint8List.fromList(_png),
            fit: BoxFit.cover,
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    expect(find.byType(RawImage), findsOneWidget);
  });

  testWidgets('GIF auto-pauses after 2 loops and resumes on tap', (
    tester,
  ) async {
    await MediaAnimationPreference.instance.setMode(MediaAnimationMode.loop);
    final gifBytes = _twoFrameGif();

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 100,
              height: 100,
              child: AnimatedMediaImage(bytes: gifBytes, fit: BoxFit.cover),
            ),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('GIF'), findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(find.byType(AnimatedMediaImage));
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });
    await tester.pump();

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });
}
