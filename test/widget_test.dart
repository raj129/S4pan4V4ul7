import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/core/presentation/theme/app_theme.dart';
import 'package:photo_vault/features/calculator/calculator.dart';
import 'package:photo_vault/core/presentation/features/utility_shell/utility_shell.dart';
import 'package:photo_vault/core/widgets/app_navigation_drawer.dart';

void main() {
  test('regular AppBars use shared Material 3 surface roles', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      expect(
        theme.appBarTheme.backgroundColor,
        theme.colorScheme.surfaceContainerLow,
      );
      expect(theme.appBarTheme.foregroundColor, theme.colorScheme.onSurface);
      expect(theme.appBarTheme.surfaceTintColor, Colors.transparent);
      expect(theme.appBarTheme.shape, isNull);
    }
  });

  testWidgets('NavigationDrawer separates its brand from its destinations', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: AppNavigationDrawer(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
            ),
          ),
        ),
      ),
    );

    final brandBottom = tester
        .getRect(find.text('Encrypted private space'))
        .bottom;
    final firstDestinationTop = tester.getRect(find.text('Chat')).top;
    expect(firstDestinationTop - brandBottom, greaterThan(16));
  });

  testWidgets('Calculator shell renders without visible vault hints', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
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
