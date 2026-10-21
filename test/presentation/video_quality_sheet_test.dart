import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/video_compressor.dart';
import 'package:photo_vault/features/chat/presentation/widgets/video_quality_sheet.dart';

void main() {
  testWidgets('renders all VideoQuality options and selects on tap', (
    tester,
  ) async {
    VideoQuality? chosen;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                chosen = await VideoQualitySheet.show(
                  context,
                  originalBytes: 15 * 1024 * 1024,
                  selected: VideoQuality.high,
                  initialEstimates: const {
                    VideoQuality.original: 15 * 1024 * 1024,
                    VideoQuality.high: 8 * 1024 * 1024,
                    VideoQuality.medium: 4 * 1024 * 1024,
                    VideoQuality.low: 2 * 1024 * 1024,
                  },
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Send video as'), findsOneWidget);
    expect(find.text('Original'), findsOneWidget);
    expect(find.text('High (1080p)'), findsOneWidget);
    expect(find.text('Medium (720p)'), findsOneWidget);
    expect(find.text('Low (480p)'), findsOneWidget);

    // Tap on Low (480p)
    await tester.tap(find.text('Low (480p)'));
    await tester.pumpAndSettle();

    expect(chosen, VideoQuality.low);
  });

  testWidgets('hides size estimates when applying one quality to many videos', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoQualitySheet(
            originalBytes: 15 * 1024 * 1024,
            selected: VideoQuality.high,
            showEstimates: false,
          ),
        ),
      ),
    );

    expect(find.text('High (1080p)'), findsOneWidget);
    expect(find.text('1080p, up to ~2.5 Mbps'), findsOneWidget);
    expect(find.textContaining('MB'), findsNothing);
    expect(find.textContaining('KB'), findsNothing);
  });
}
