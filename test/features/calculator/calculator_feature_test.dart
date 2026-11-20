import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/presentation/theme/app_theme.dart';
import 'package:photo_vault/features/calculator/domain/models/secret_entry_config.dart';
import 'package:photo_vault/features/calculator/presentation/calculator_feature.dart';
import 'package:photo_vault/features/calculator/presentation/theme/calculator_theme.dart';
import 'package:photo_vault/features/calculator/presentation/widgets/calc_button.dart';
import 'package:photo_vault/features/calculator/presentation/widgets/display_panel.dart';
import 'package:photo_vault/features/calculator/presentation/widgets/keypad_layouts.dart';

void main() {
  /// Restricts a text match to the display, so keypad labels don't match too.
  Finder displayText(String text) =>
      find.descendant(of: find.byType(DisplayPanel), matching: find.text(text));

  Future<void> pumpCalculator(
    WidgetTester tester, {
    VoidCallback? onVaultTriggerRequested,
    SecretEntryConfig secretEntryConfig = const SecretEntryConfig(),
    Future<bool> Function(String pin)? onStealthPinSubmitted,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: Scaffold(
          body: SizedBox(
            height: 700,
            child: CalculatorFeature(
              secretEntryConfig: secretEntryConfig,
              onVaultTriggerRequested: onVaultTriggerRequested ?? () {},
              onStealthPinSubmitted: onStealthPinSubmitted,
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

  testWidgets('calculator keys retain the dedicated calculator palette', (
    tester,
  ) async {
    await pumpCalculator(tester);

    final digit = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('digit-2')),
            matching: find.byType(Material),
          )
          .first,
    );
    final operator = tester.widget<Material>(
      find
          .descendant(
            of: find.byKey(const ValueKey<String>('add')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(digit.color, CalculatorTheme.keyBackground);
    expect(operator.color, CalculatorTheme.accent);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('pointer-up after removal does not update disposed button', (
    tester,
  ) async {
    var showButton = true;
    var pressEndCount = 0;
    late StateSetter setParentState;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            setParentState = setState;
            return Scaffold(
              body: showButton
                  ? Center(
                      child: CalcButton(
                        label: '1',
                        onTap: () {},
                        onPressEnd: () => pressEndCount++,
                      ),
                    )
                  : const SizedBox.shrink(),
            );
          },
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CalcButton)),
    );
    setParentState(() => showButton = false);
    await tester.pump();

    await gesture.up();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(pressEndCount, 1);
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

  testWidgets('holdPinConfirm (Method 99) submits PIN when MR is pressed and 7 + = still works', (
    tester,
  ) async {
    String? submittedPin;
    var defaultTriggered = 0;
    await pumpCalculator(
      tester,
      secretEntryConfig: SecretEntryConfig.defaultsFor(
        SecretEntryMethod.holdPinConfirm,
        oneHandedEnabled: true,
      ),
      onVaultTriggerRequested: () => defaultTriggered++,
      onStealthPinSubmitted: (pin) async {
        submittedPin = pin;
        return true;
      },
    );

    final equals = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>(kEqualsKeyId))),
    );
    await tester.pump(const Duration(milliseconds: 900));
    await equals.up();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('digit-1')));
    await tester.tap(find.byKey(const ValueKey<String>('digit-9')));
    await tester.tap(find.byKey(const ValueKey<String>('digit-5')));
    await tester.tap(find.byKey(const ValueKey<String>('digit-8')));
    await tester.tap(find.byKey(const ValueKey<String>(kMemoryRecallKeyId)));
    await tester.pumpAndSettle();

    expect(submittedPin, '1958');

    // Wait for cooldown, then verify default 7 + = still works as fallback.
    await tester.pump(const Duration(milliseconds: 900));
    final seven = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>(kSevenKeyId))),
    );
    final equalsFallback = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey<String>(kEqualsKeyId))),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    expect(defaultTriggered, 1);
    await seven.up();
    await equalsFallback.up();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'secretMathEquation (Method 4) submits trailing PIN on hold and evaluates normally if invalid',
    (tester) async {
      String? submittedPin;
      await pumpCalculator(
        tester,
        secretEntryConfig: SecretEntryConfig.defaultsFor(
          SecretEntryMethod.secretMathEquation,
        ),
        onStealthPinSubmitted: (pin) async {
          submittedPin = pin;
          return pin == '1958';
        },
      );

      // Invalid PIN evaluates normally on release with no error.
      await tester.tap(find.byKey(const ValueKey<String>('digit-1')));
      await tester.tap(find.byKey(const ValueKey<String>('add')));
      await tester.tap(find.byKey(const ValueKey<String>('digit-1')));
      await tester.tap(find.byKey(const ValueKey<String>('digit-2')));
      await tester.tap(find.byKey(const ValueKey<String>('digit-3')));
      await tester.tap(find.byKey(const ValueKey<String>('digit-4')));
      await tester.pump();

      final equalsInvalid = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>(kEqualsKeyId))),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      await equalsInvalid.up();
      await tester.pump();

      expect(submittedPin, '1234');
      expect(displayText('1235'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 900));

      // Valid PIN triggers direct unlock.
      await tester.tap(find.byKey(const ValueKey<String>('clear')));
      await tester.tap(find.byKey(const ValueKey<String>('digit-1')));
      await tester.tap(find.byKey(const ValueKey<String>('digit-9')));
      await tester.tap(find.byKey(const ValueKey<String>('digit-5')));
      await tester.tap(find.byKey(const ValueKey<String>('digit-8')));
      await tester.pump();

      final equalsValid = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey<String>(kEqualsKeyId))),
      );
      await tester.pump(const Duration(milliseconds: 1100));
      await equalsValid.up();
      await tester.pumpAndSettle();

      expect(submittedPin, '1958');
    },
  );
}
