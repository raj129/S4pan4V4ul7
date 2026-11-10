import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/core/widgets/inline_media_preview.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
}
