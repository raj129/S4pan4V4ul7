import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:photo_vault/features/chat/presentation/widgets/animated_emoji.dart';

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

  testWidgets('sizes emoji-only messages by emoji count', (tester) async {
    for (final (text, expectedSize) in [
      ('😀', 67.2),
      ('😀😀', 76.8),
      ('😀😀😀😀', 76.8),
      ('😀😀😀😀😀', 67.2),
    ]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedEmojiText(text: text, playbackId: text, size: 48),
          ),
        ),
      );
      await tester.pump();

      final box = tester.widget<SizedBox>(
        find.byKey(const ValueKey('emoji-box-0')),
      );
      expect(box.width, expectedSize, reason: text);
      expect(box.height, expectedSize, reason: text);
    }
  });

  testWidgets('keeps the settled emoji centered in the animation-sized box', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AnimatedEmojiText(text: '😀', playbackId: 'finished'),
        ),
      ),
    );
    final boxFinder = find.byKey(const ValueKey('emoji-box-0'));
    final animationFinder = find.byKey(const ValueKey('emoji-animation-0'));
    final animatedSize = tester.widget<SizedBox>(boxFinder).width;
    await tester.pumpAndSettle();

    expect(tester.widget<Opacity>(animationFinder).opacity, 1);
    expect(find.byType(FittedBox), findsNothing);
    await tester.pump(
      AnimatedEmojiText.staticEmojiDelay - const Duration(milliseconds: 1),
    );
    expect(find.byType(FittedBox), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));

    expect(find.text('😀'), findsOneWidget);
    expect(tester.widget<Opacity>(animationFinder).opacity, 0);
    expect(find.byType(FittedBox), findsOneWidget);
    expect(tester.widget<SizedBox>(boxFinder).width, animatedSize);
    expect(animatedSize, closeTo(67.2, 0.01));
  });

  testWidgets('remounted played emoji stays static until tapped', (
    tester,
  ) async {
    Widget app() => const MaterialApp(
      home: Scaffold(
        body: AnimatedEmojiText(text: '😀', playbackId: 'remounted'),
      ),
    );

    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(app());
    final animationOpacity = find.byKey(const ValueKey('emoji-animation-0'));
    expect(tester.widget<Opacity>(animationOpacity).opacity, 0);
    expect(find.byType(FittedBox), findsOneWidget);

    await tester.pumpAndSettle();
    expect(tester.widget<Opacity>(animationOpacity).opacity, 0);
    expect(find.text('😀'), findsOneWidget);

    await tester.tap(find.byType(AnimatedEmojiText));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<Opacity>(animationOpacity).opacity, 1);
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
