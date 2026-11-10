import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/media/animated_media.dart';
import 'package:photo_vault/core/widgets/animated_media_image.dart';
import 'package:shared_preferences/shared_preferences.dart';

// 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

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
}
