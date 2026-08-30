import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/calculator/presentation/calculator_feature.dart';
import 'package:photo_vault/features/calculator/presentation/widgets/display_panel.dart';
import 'package:photo_vault/features/calculator/presentation/widgets/keypad_layouts.dart';

void main() {
  /// Restricts a text match to the display, so keypad labels don't match too.
  Finder displayText(String text) => find.descendant(
    of: find.byType(DisplayPanel),
    matching: find.text(text),
  );

  Future<void> pumpCalculator(
    WidgetTester tester, {
    VoidCallback? onVaultTriggerRequested,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: CalculatorFeature(
              onVaultTriggerRequested: onVaultTriggerRequested ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('computes an expression from key taps', (tester) async {
    await pumpCalculator(tester);

    await tester.tap(find.byKey(const ValueKey<String>('digit-2')));
    await tester.tap(find.byKey(const ValueKey<String>('add')));
    await tester.tap(find.byKey(const ValueKey<String>('digit-3')));
    await tester.pump();

    expect(displayText('2+3'), findsOneWidget);
    expect(displayText('= 5'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>(kEqualsKeyId)));
    await tester.pump();

    expect(displayText('5'), findsOneWidget);
  });

  testWidgets('AC clears the display', (tester) async {
    await pumpCalculator(tester);

    await tester.tap(find.byKey(const ValueKey<String>('digit-9')));
    await tester.pump();
    expect(displayText('9'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('clear')));
    await tester.pump();
    expect(displayText('0'), findsOneWidget);
  });

  testWidgets('scientific rows appear only when toggled', (tester) async {
    await pumpCalculator(tester);

    expect(find.byKey(const ValueKey<String>('sin')), findsNothing);

    await tester.tap(find.text('fx'));
    await tester.pump();

    expect(find.byKey(const ValueKey<String>('sin')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('angle-unit')), findsOneWidget);
  });

  testWidgets('holding 7 and = together opens the vault', (tester) async {
    var triggered = 0;
    await pumpCalculator(tester, onVaultTriggerRequested: () => triggered++);

    final seven = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>(kSevenKeyId))),
    );
    final equals = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>(kEqualsKeyId))),
    );

    await tester.pump(const Duration(milliseconds: 1300));
    expect(triggered, 1);

    await seven.up();
    await equals.up();
    await tester.pumpAndSettle();
  });

  testWidgets('holding only 7 does not open the vault', (tester) async {
    var triggered = 0;
    await pumpCalculator(tester, onVaultTriggerRequested: () => triggered++);

    final seven = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>(kSevenKeyId))),
    );
    await tester.pump(const Duration(milliseconds: 2000));
    expect(triggered, 0);

    await seven.up();
    await tester.pumpAndSettle();
  });

  testWidgets('no vault hint is visible in the UI', (tester) async {
    await pumpCalculator(tester);

    expect(find.textContaining('vault', findRichText: true), findsNothing);
    expect(find.textContaining('Vault'), findsNothing);
    expect(find.textContaining('Hold'), findsNothing);
  });
}
