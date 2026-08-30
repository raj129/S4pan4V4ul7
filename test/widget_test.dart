import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/features/calculator/calculator.dart';
import 'package:photo_vault/presentation/features/utility_shell/utility_shell.dart';

void main() {
  testWidgets('Calculator shell renders without visible vault hints', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: UtilityShell(
          title: 'Calculator',
          child: CalculatorFeature(onVaultTriggerRequested: () {}),
        ),
      ),
    );

    expect(find.text('Calculator'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('AC'), findsOneWidget);
    expect(find.text('Private vault entry'), findsNothing);
    expect(
      find.text('Hold 7 and = together to open the passcode screen.'),
      findsNothing,
    );
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
  });
}
