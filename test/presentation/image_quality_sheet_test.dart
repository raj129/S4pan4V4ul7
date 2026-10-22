import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/image_compressor.dart';
import 'package:photo_vault/features/chat/presentation/widgets/image_quality_sheet.dart';

void main() {
  Future<ImageQuality?> openAndTap(
    WidgetTester tester, {
    required ImageQuality selected,
    required String tapLabel,
  }) async {
    ImageQuality? result;
    var opened = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              opened = true;
              result = await ImageQualitySheet.show(
                context,
                originalBytes: 4 * 1024 * 1024,
                selected: selected,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);

    await tester.tap(find.text(tapLabel));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('choosing a different quality returns it', (tester) async {
    final chosen = await openAndTap(
      tester,
      selected: ImageQuality.high,
      tapLabel: 'Low',
    );

    expect(chosen, ImageQuality.low);
  });

  testWidgets('choosing the already-selected quality still sends', (
    tester,
  ) async {
    // A radio ignores a tap on its current value, which used to leave the
    // sheet open and silently drop the photo.
    final chosen = await openAndTap(
      tester,
      selected: ImageQuality.high,
      tapLabel: 'High',
    );

    expect(chosen, ImageQuality.high);
  });

  testWidgets('every quality is offered with a size hint', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ImageQualitySheet(
            originalBytes: 4 * 1024 * 1024,
            selected: ImageQuality.medium,
          ),
        ),
      ),
    );

    for (final quality in ImageQuality.values) {
      expect(find.text(quality.label), findsOneWidget);
    }
    expect(find.textContaining('4.0 MB'), findsWidgets);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('displays exact estimated sizes when initialEstimates provided', (
    tester,
  ) async {
    final estimates = {
      ImageQuality.original: 4 * 1024 * 1024,
      ImageQuality.high: 350 * 1024,
      ImageQuality.medium: 200 * 1024,
      ImageQuality.low: 80 * 1024,
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImageQualitySheet(
            originalBytes: 4 * 1024 * 1024,
            selected: ImageQuality.high,
            initialEstimates: estimates,
          ),
        ),
      ),
    );

    expect(find.textContaining('350 KB'), findsOneWidget);
    expect(find.textContaining('200 KB'), findsOneWidget);
    expect(find.textContaining('80 KB'), findsOneWidget);
  });
}
