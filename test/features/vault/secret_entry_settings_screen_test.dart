import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/features/calculator/domain/models/secret_entry_config.dart';
import 'package:photo_vault/features/vault/presentation/screens/settings/secret_entry_settings_screen.dart';

void main() {
  testWidgets('allows choosing a secret entry method and custom keys', (
    tester,
  ) async {
    final repo = InMemorySettingsRepository();
    var settingsChangedCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: SecretEntrySettingsScreen(
          settingsRepository: repo,
          onSettingsChanged: () async => settingsChangedCalls++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Change default first hold key from 7 to 1.
    await tester.tap(find.byKey(const Key('default-primary-key-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('picker-key-digit-1')));
    await tester.pumpAndSettle();

    var saved = await repo.getSecretEntryConfig();
    expect(saved.defaultPrimaryKeyId, 'digit-1');
    expect(settingsChangedCalls, 1);

    // Enable one-handed mode.
    final switchFinder = find.byKey(const Key('custom-secret-entry-switch'));
    await tester.scrollUntilVisible(switchFinder, 200);
    await tester.ensureVisible(switchFinder);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    // Select Method 99 (Hold + PIN + Confirm Key) and verify default key is preserved.
    final methodFinder = find.byKey(
      Key('secret-method-${SecretEntryMethod.holdPinConfirm.id}'),
    );
    await tester.scrollUntilVisible(methodFinder, 200);
    await tester.ensureVisible(methodFinder);
    await tester.tap(methodFinder);
    await tester.pumpAndSettle();

    saved = await repo.getSecretEntryConfig();
    expect(saved.defaultPrimaryKeyId, 'digit-1');
    expect(saved.oneHandedEnabled, isTrue);
    expect(saved.method, SecretEntryMethod.holdPinConfirm);
    expect(settingsChangedCalls, 2);

    // Change confirm key from MR to M+.
    final confirmPicker = find.byKey(const Key('confirm-key-picker'));
    await tester.scrollUntilVisible(confirmPicker, 200);
    await tester.ensureVisible(confirmPicker);
    await tester.pumpAndSettle();
    await tester.tap(confirmPicker);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('picker-key-memory-add')));
    await tester.pumpAndSettle();

    saved = await repo.getSecretEntryConfig();
    expect(saved.oneHandedEnabled, isTrue);
    expect(saved.confirmKeyId, 'memory-add');
    expect(settingsChangedCalls, 3);
  });
}
