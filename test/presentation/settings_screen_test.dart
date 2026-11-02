import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/core/platform/battery_optimization.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/presentation/screens/settings/settings_screen.dart';

class _FakeUnlock implements UnlockVaultUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeBattery implements BatteryOptimization {
  _FakeBattery({required this.exempt});
  bool exempt;
  int requests = 0;

  @override
  Future<bool> isExempt() async => exempt;

  @override
  Future<bool> requestExemption() async {
    requests++;
    exempt = true;
    return true;
  }
}

void main() {
  late InMemorySettingsRepository settings;
  late List<bool> lastSeenChanges;

  Future<void> pump(
    WidgetTester tester,
    BatteryOptimization battery, {
    Future<void> Function()? onTestNotification,
  }) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    settings = InMemorySettingsRepository();
    lastSeenChanges = [];
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          mode: UserMode.localOnly,
          settingsRepository: settings,
          unlockVaultUseCase: _FakeUnlock(),
          pinValidator: PinValidator(),
          onSettingsChanged: () async {},
          onShowLastSeenChanged: (v) async => lastSeenChanges.add(v),
          onTestNotification: onTestNotification,
          batteryOptimization: battery,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Show last seen toggle persists and notifies chat', (
    tester,
  ) async {
    await pump(tester, _FakeBattery(exempt: true));
    expect(find.text('Show last seen'), findsOneWidget);
    await tester.tap(find.text('Show last seen'));
    await tester.pumpAndSettle();
    expect(await settings.isShowLastSeenEnabled(), isFalse);
    expect(lastSeenChanges, [false]);
    expect(find.textContaining("won't see other people's"), findsOneWidget);
  });

  testWidgets('timeout choices and simplified alert settings persist', (
    tester,
  ) async {
    final testedBodies = <String>[];
    await pump(
      tester,
      _FakeBattery(exempt: true),
      onTestNotification: () async {
        testedBodies.add(await settings.getIncomingChatAlertText());
      },
    );

    expect(await settings.getAutoLockTimeoutSeconds(), 10);
    await tester.tap(find.byKey(const Key('auto-lock-timeout-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('5 sec'), findsOneWidget);
    expect(find.text('10 sec'), findsNWidgets(2));
    expect(find.text('1 min'), findsOneWidget);
    await tester.tap(find.text('30 sec').last);
    await tester.pumpAndSettle();
    expect(await settings.getAutoLockTimeoutSeconds(), 30);

    await tester.enterText(
      find.byKey(const Key('incoming-chat-alert-text-field')),
      'A message is waiting',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(await settings.getIncomingChatAlertText(), 'A message is waiting');

    await tester.tap(find.byKey(const Key('clear-incoming-chat-alert-button')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(await settings.getIncomingChatAlertText(), isEmpty);

    await tester.ensureVisible(
      find.byKey(const Key('test-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(testedBodies, ['']);
  });

  testWidgets('restricted background shows a fix that asks for exemption', (
    tester,
  ) async {
    final battery = _FakeBattery(exempt: false);
    await pump(tester, battery);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Run in background'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Restricted by battery saver'), findsOneWidget);
    await tester.tap(find.text('Run in background'));
    await tester.pumpAndSettle();
    expect(find.text('Keep running in background'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.pumpAndSettle();
    expect(battery.requests, 1);
    await tester.drag(find.byType(ListView).first, const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Run in background'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Allowed.'), findsOneWidget);
  });

  testWidgets('Change PIN goes straight to the flow without a re-auth prompt', (
    tester,
  ) async {
    await pump(tester, _FakeBattery(exempt: true));
    expect(
      find.text('Enter your current PIN, then choose a new one.'),
      findsOneWidget,
    );
  });
}
