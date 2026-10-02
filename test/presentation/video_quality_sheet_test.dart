import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/video_compressor.dart';
import 'package:photo_vault/presentation/widgets/chat/video_quality_sheet.dart';

void main() {
  testWidgets('shows original and each compressed quality', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoQualitySheet(
            selected: ChatVideoQuality.medium,
            originalBytes: 10 * 1024 * 1024,
          ),
        ),
      ),
    );

    for (final quality in ChatVideoQuality.values) {
      expect(find.text(quality.label), findsOneWidget);
    }
    expect(find.textContaining('10.0 MB'), findsOneWidget);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('hides compression options when the platform cannot transcode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: VideoQualitySheet(
            selected: ChatVideoQuality.original,
            originalBytes: 1024,
            allowCompression: false,
          ),
        ),
      ),
    );

    expect(find.text('Original'), findsOneWidget);
    expect(find.text('High'), findsNothing);
    expect(find.text('Medium'), findsNothing);
    expect(find.text('Low'), findsNothing);
  });
}
