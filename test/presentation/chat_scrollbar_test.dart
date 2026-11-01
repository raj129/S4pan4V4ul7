import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_scrollbar.dart';

void main() {
  group('ChatScrollbarGeometry', () {
    const geo = ChatScrollbarGeometry(trackHeight: 544, thumbHeight: 44);

    test('latest (1) is at the bottom and oldest (0) at the top', () {
      expect(geo.thumbTop(1), 500);
      expect(geo.thumbTop(0), 0);
    });

    test('fractionAt is the inverse of thumbTop', () {
      for (final f in [0.0, 0.25, 0.5, 0.9, 1.0]) {
        expect(geo.fractionAt(geo.thumbTop(f)), closeTo(f, 1e-9));
      }
    });

    test('clamps out-of-range input', () {
      expect(geo.thumbTop(2), 500);
      expect(geo.fractionAt(-50), 0);
      expect(geo.fractionAt(9999), 1);
    });

    test('a track shorter than the thumb has no travel and no NaN', () {
      const tiny = ChatScrollbarGeometry(trackHeight: 30, thumbHeight: 44);
      expect(tiny.usable, 0);
      expect(tiny.thumbTop(0.5), 0);
      expect(tiny.fractionAt(10), 1);
    });
  });

  group('ChatScrollbar', () {
    Future<
      ({
        ValueNotifier<double?> position,
        List<double> previews,
        List<double> jumps,
      })
    >
    pump(WidgetTester tester, {double start = 1}) async {
      final position = ValueNotifier<double?>(start);
      final visible = ValueNotifier<bool>(true);
      final previews = <double>[];
      final jumps = <double>[];
      addTearDown(position.dispose);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: 200,
                height: 544,
                child: ChatScrollbar(
                  position: position,
                  visible: visible,
                  dateAt: (_) async => null,
                  onDragPreview: previews.add,
                  onJump: jumps.add,
                ),
              ),
            ),
          ),
        ),
      );
      return (position: position, previews: previews, jumps: jumps);
    }

    Finder thumb() => find.byType(GestureDetector).first;

    testWidgets('thumb starts at the bottom when at the latest message', (
      tester,
    ) async {
      await pump(tester);
      final rect = tester.getRect(thumb());
      // 12px grab padding below the 44px thumb that ends at the track bottom.
      expect(rect.bottom, closeTo(544 + 12, 0.5));
    });

    testWidgets('dragging is absolute: thumb follows the finger 1:1', (
      tester,
    ) async {
      final r = await pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(thumb()));
      // Move up by half the travel (500 / 2), in small steps.
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(const Offset(0, -25));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await tester.pump();
      expect(r.jumps.single, closeTo(0.5, 0.02));
    });

    testWidgets('previews while dragging are throttled and live', (
      tester,
    ) async {
      final r = await pump(tester);
      final gesture = await tester.startGesture(tester.getCenter(thumb()));
      for (var i = 0; i < 20; i++) {
        await gesture.moveBy(const Offset(0, -10));
        await tester.pump(const Duration(milliseconds: 16));
      }
      // 20 moves over ~320ms: far fewer previews than moves, but at least one
      // before release so the list follows the finger.
      expect(r.previews, isNotEmpty);
      expect(r.previews.length, lessThan(6));
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 200));
      expect(r.jumps, hasLength(1));
    });

    testWidgets('hidden when the position is unknown', (tester) async {
      final r = await pump(tester);
      r.position.value = null;
      await tester.pump();
      expect(find.byType(GestureDetector), findsNothing);
    });
  });
}
