import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:photo_vault/core/media/animated_media.dart';
import 'package:photo_vault/core/platform/battery_optimization.dart';
import 'package:photo_vault/core/platform/hdr_preview_capability.dart';
import 'package:photo_vault/core/platform/screenshot_protection.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/presentation/screens/settings/notification_settings_screen.dart';
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

class _FakeScreenshotProtection implements ScreenshotProtectionController {
  final changes = <bool>[];

  @override
  bool get isSupportedPlatform => true;

  @override
  Future<void> setEnabled(bool enabled) async {
    changes.add(enabled);
  }
}

void main() {
  late InMemorySettingsRepository settings;
  late List<bool> lastSeenChanges;

  Future<void> pump(
    WidgetTester tester,
    BatteryOptimization battery, {
    Future<void> Function()? onTestNotification,
    Future<void> Function()? onNotificationSettingsChanged,
    ScreenshotProtectionController? screenshotProtection,
  }) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    settings = InMemorySettingsRepository();
    lastSeenChanges = [];
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => SettingsScreen(
            mode: UserMode.localOnly,
            settingsRepository: settings,
            unlockVaultUseCase: _FakeUnlock(),
            pinValidator: PinValidator(),
            onSettingsChanged: () async {},
            onShowLastSeenChanged: (v) async => lastSeenChanges.add(v),
            screenshotProtection:
                screenshotProtection ?? const AndroidScreenshotProtection(),
            batteryOptimization: battery,
          ),
          routes: [
            GoRoute(
              path: 'notifications',
              builder: (context, state) => NotificationSettingsScreen(
                settingsRepository: settings,
                onTestNotification: onTestNotification,
                onNotificationSettingsChanged: onNotificationSettingsChanged,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('screenshot protection defaults on and can be disabled', (
    tester,
  ) async {
    final protection = _FakeScreenshotProtection();
    await pump(
      tester,
      _FakeBattery(exempt: true),
      screenshotProtection: protection,
    );

    expect(find.text('Screenshot protection'), findsOneWidget);
    expect(await settings.isScreenshotProtectionEnabled(), isTrue);
    await tester.tap(find.text('Screenshot protection'));
    await tester.pumpAndSettle();

    expect(await settings.isScreenshotProtectionEnabled(), isFalse);
    expect(protection.changes, [false]);
    expect(
      find.text('Screenshots and screen recordings are allowed.'),
      findsOneWidget,
    );
  });

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

  testWidgets('media preview settings persist for chat and vault', (
    tester,
  ) async {
    const hdrChannel = MethodChannel('photo_vault/hdr_preview');
    final previousPlatform = debugDefaultTargetPlatformOverride;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    HdrPreviewCapability.instance.resetForTesting();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      hdrChannel,
      (call) async => call.method == 'isSupported' ? true : null,
    );
    SharedPreferences.setMockInitialValues({});
    try {
      await pump(tester, _FakeBattery(exempt: true));
      await tester.scrollUntilVisible(
        find.text('Motion Photo playback'),
        240,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('motion-photo-once-mode')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(
        find.byKey(const Key('motion-photo-once-mode')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('motion-photo-once-mode')));
      await tester.pumpAndSettle();
      expect(
        MediaAnimationPreference.instance.mode.value,
        MediaAnimationMode.once,
      );

      expect(HdrPreviewCapability.instance.available.value, isTrue);
      expect(find.byType(Scrollable), findsWidgets);
      await tester.scrollUntilVisible(
        find.text('HDR photo preview'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('HDR photo preview'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('HDR photo preview'));
      await tester.pumpAndSettle();
      expect(HdrPreviewPreference.instance.enabled.value, isFalse);
      expect(await settings.isHdrPhotoPreviewEnabled(), isFalse);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('settings.media_animation_mode'), 'once');
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        hdrChannel,
        null,
      );
      debugDefaultTargetPlatformOverride = previousPlatform;
      HdrPreviewCapability.instance.resetForTesting();
      HdrPreviewPreference.instance.resetForTesting();
    }
  });

  testWidgets('notification settings navigate, list, and edit each type', (
    tester,
  ) async {
    final testedTitles = <String>[];
    final testedBodies = <String>[];
    var locationNotificationRefreshes = 0;
    await pump(
      tester,
      _FakeBattery(exempt: true),
      onTestNotification: () async {
        testedTitles.add(await settings.getIncomingChatAlertTitle());
        testedBodies.add(await settings.getIncomingChatAlertText());
      },
      onNotificationSettingsChanged: () async {
        locationNotificationRefreshes++;
      },
    );
    tester.view.physicalSize = const Size(1080, 7000);
    await tester.pumpAndSettle();

    expect(await settings.getAutoLockTimeoutSeconds(), 10);
    await tester.tap(find.byKey(const Key('auto-lock-timeout-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('5 sec'), findsOneWidget);
    expect(find.text('10 sec'), findsNWidgets(2));
    expect(find.text('1 min'), findsOneWidget);
    await tester.tap(find.text('30 sec').last);
    await tester.pumpAndSettle();
    expect(await settings.getAutoLockTimeoutSeconds(), 30);

    expect(
      find.byKey(const Key('notification-settings-navigation-tile')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const Key('notification-settings-navigation-tile')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
    expect(
      find.byKey(const Key('incoming-chat-notification-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('background-location-notification-card')),
      findsOneWidget,
    );
    expect(await settings.getIncomingChatAlertTitle(), isEmpty);
    expect(await settings.getIncomingChatAlertText(), isEmpty);
    expect(await settings.getBackgroundLocationAlertTitle(), isEmpty);
    expect(
      await settings.getBackgroundLocationAlertText(),
      'Syncing in background',
    );

    await tester.ensureVisible(
      find.byKey(const Key('incoming-chat-alert-title-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incoming-chat-alert-title-field')));
    await tester.enterText(
      find.byKey(const Key('incoming-chat-alert-title-field')),
      'Private chat',
    );
    await tester.ensureVisible(
      find.byKey(const Key('incoming-chat-alert-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incoming-chat-alert-field')));
    await tester.enterText(
      find.byKey(const Key('incoming-chat-alert-field')),
      'A message is waiting',
    );
    await tester.ensureVisible(
      find.byKey(const Key('background-location-alert-title-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('background-location-alert-title-field')),
    );
    await tester.enterText(
      find.byKey(const Key('background-location-alert-title-field')),
      'Location',
    );
    await tester.ensureVisible(
      find.byKey(const Key('background-location-alert-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('background-location-alert-field')));
    await tester.enterText(
      find.byKey(const Key('background-location-alert-field')),
      'Sharing is active',
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('incoming-chat-alert-field')))
          .controller!
          .text,
      'A message is waiting',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(await settings.getIncomingChatAlertTitle(), 'Private chat');
    expect(await settings.getIncomingChatAlertText(), 'A message is waiting');
    expect(await settings.getBackgroundLocationAlertTitle(), 'Location');
    expect(
      await settings.getBackgroundLocationAlertText(),
      'Sharing is active',
    );
    expect(locationNotificationRefreshes, greaterThan(0));

    await tester.tap(find.byKey(const Key('clear-incoming-chat-alert-button')));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    expect(await settings.getIncomingChatAlertTitle(), 'Private chat');
    expect(await settings.getIncomingChatAlertText(), isEmpty);
    expect(await settings.getBackgroundLocationAlertTitle(), 'Location');
    expect(
      await settings.getBackgroundLocationAlertText(),
      'Sharing is active',
    );

    await tester.ensureVisible(
      find.byKey(const Key('test-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(testedTitles, ['Private chat']);
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
