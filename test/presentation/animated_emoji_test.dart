import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:photo_vault/presentation/widgets/chat/animated_emoji.dart';

void main() {
  setUp(() {
    AnimatedEmojiRegistry.debugSetIndex([
      '1f600',
      '1f44d',
      '1f44d_1f3fd',
      '2764_fe0f',
      '1f468_200d_1f469_200d_1f467',
    ]);
    AnimatedEmojiText.debugResetPlayback();
  });

  tearDown(AnimatedEmojiRegistry.debugReset);

  group('AnimatedEmojiRegistry.assetFor', () {
    test('maps a plain emoji', () {
      expect(
        AnimatedEmojiRegistry.assetFor('😀'),
        'assets/animated_emoji/1f600.json',
      );
    });

    test('keeps skin-tone modifiers', () {
      expect(
        AnimatedEmojiRegistry.assetFor('👍🏽'),
        'assets/animated_emoji/1f44d_1f3fd.json',
      );
    });

    test('matches hearts with or without the FE0F selector', () {
      const expected = 'assets/animated_emoji/2764_fe0f.json';
      expect(AnimatedEmojiRegistry.assetFor('❤️'), expected);
      expect(AnimatedEmojiRegistry.assetFor('❤'), expected);
    });

    test('maps ZWJ sequences', () {
      expect(
        AnimatedEmojiRegistry.assetFor('👨‍👩‍👧'),
        'assets/animated_emoji/1f468_200d_1f469_200d_1f467.json',
      );
    });

    test('returns null when there is no animation', () {
      expect(AnimatedEmojiRegistry.assetFor('🦖'), isNull);
    });
  });

  testWidgets('renders animated and static emoji side by side', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnimatedEmojiText(text: '😀🦖', playbackId: 'm1'),
        ),
      ),
    );

    expect(find.byType(LottieBuilder), findsOneWidget);
    expect(find.text('🦖'), findsOneWidget);
    expect(find.bySemanticsLabel('😀🦖'), findsOneWidget);
  });

  testWidgets('emoji without a Google animation still bounce, once', (
    tester,
  ) async {
    Widget app(String id) => MaterialApp(
      home: Scaffold(
        body: AnimatedEmojiText(key: ValueKey(id), text: '🦖', playbackId: id),
      ),
    );

    double scaleOf() => tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byType(AnimatedEmojiText),
            matching: find.byType(Transform),
          ),
        )
        .last
        .transform
        .getMaxScaleOnAxis();

    await tester.pumpWidget(app('m1'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(scaleOf(), greaterThan(1.01));
    await tester.pumpAndSettle();
    expect(scaleOf(), closeTo(1, 0.001));

    // Tapping replays it.
    await tester.tap(find.text('🦖'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(scaleOf(), greaterThan(1.01));
    await tester.pumpAndSettle();
  });

  group('bundled assets', () {
    setUp(AnimatedEmojiRegistry.debugReset);

    test('index loads and animations parse', () async {
      await AnimatedEmojiRegistry.ensureLoaded();
      for (final e in ['😂', '😀', '👍', '❤️', '🙏', '🐒']) {
        final path = AnimatedEmojiRegistry.assetFor(e);
        expect(path, isNotNull, reason: e);
        final composition = await LottieComposition.fromByteData(
          await rootBundle.load(path!),
        );
        expect(composition.duration, greaterThan(Duration.zero), reason: e);
      }
      // Google publishes no animation for these; they use the bounce.
      expect(AnimatedEmojiRegistry.assetFor('🐱'), isNull);
    });
  });
}
