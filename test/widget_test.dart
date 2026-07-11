import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/presentation/app/vault_app.dart';

void main() {
  testWidgets('Welcome screen renders correct CTAs', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const VaultApp());
    // Allow the router redirect to settle.
    await tester.pumpAndSettle();

    expect(find.text('Continue locally'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text("What's the difference?"), findsOneWidget);
  });
}
