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
import 'package:photo_vault/core/widgets/base_screen_shell.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/features/vault/domain/entities/incoming_chat_alert_preferences.dart';
import 'package:photo_vault/features/chat/domain/entities/ring_alert_preferences.dart';
import 'package:photo_vault/features/chat/domain/repositories/ring_alert_preferences_repository.dart';
import 'package:photo_vault/features/chat/presentation/screens/ring_alert_settings_screen.dart';
import 'package:photo_vault/features/vault/presentation/screens/settings/notification_settings_screen.dart';
import 'package:photo_vault/features/vault/presentation/screens/settings/notification_type_settings_screen.dart';
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

class _FakeRingAlertPreferencesRepository
    implements RingAlertPreferencesRepository {
  RingAlertPreferences preferences = const RingAlertPreferences();

  @override
  Future<RingAlertPreferences> getPreferences(String uid) async => preferences;

  @override
  Future<void> savePreferences(String uid, RingAlertPreferences next) async {
    preferences = next;
  }
}

void main() {
  late InMemorySettingsRepository settings;
  late _FakeRingAlertPreferencesRepository ringSettings;
  late List<bool> lastSeenChanges;

  Future<void> pump(
    WidgetTester tester,
    BatteryOptimization battery, {
    ChatNotificationTester? onTestNotification,
    Future<void> Function({required String title, required String body})?
    onTestBackgroundLocation,
    Future<void> Function()? onNotificationSettingsChanged,
    ScreenshotProtectionController? screenshotProtection,
  }) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    settings = InMemorySettingsRepository();
    ringSettings = _FakeRingAlertPreferencesRepository();
    lastSeenChanges = [];
    final router = GoRouter(
      initialLocation: '/settings',
      routes: [
        GoRoute(
          path: '/settings',
          builder: (context, state) => SettingsScreen(
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
              builder: (context, state) => const NotificationSettingsScreen(),
              routes: [
                GoRoute(
                  path: 'messages',
                  builder: (context, state) => NotificationTypeSettingsScreen(
                    type: NotificationConfigurationType.chatMessages,
                    settingsRepository: settings,
                    onTestChatNotification: onTestNotification,
                  ),
                ),
                GoRoute(
                  path: 'background-location',
                  builder: (context, state) => NotificationTypeSettingsScreen(
                    type: NotificationConfigurationType.backgroundLocation,
                    settingsRepository: settings,
                    onTestBackgroundLocation: onTestBackgroundLocation,
                    onNotificationSettingsChanged:
                        onNotificationSettingsChanged,
                  ),
                ),
                GoRoute(
                  path: 'ring-requests',
                  builder: (context, state) => RingAlertSettingsScreen(
                    repository: ringSettings,
                    uid: 'test-user',
                  ),
                ),
              ],
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

  testWidgets('backup and vault recovery share one settings entry', (
    tester,
  ) async {
    await pump(tester, _FakeBattery(exempt: true));

    expect(find.text('Google mode & restore'), findsNothing);
    await tester.scrollUntilVisible(
      find.byKey(const Key('settings-backup-tile')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.byKey(const Key('settings-backup-tile')), findsOneWidget);
    expect(
      tester
          .widget<ListTile>(find.byKey(const Key('settings-backup-tile')))
          .title,
      isA<Text>().having((text) => text.data, 'label', 'Backup & restore'),
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

  testWidgets('notification flow edits, tests, resets, and returns correctly', (
    tester,
  ) async {
    final testedTitles = <String>[];
    final testedBodies = <String>[];
    final testedPreferences = <IncomingChatAlertPreferences>[];
    final backgroundTests = <({String title, String body})>[];
    var locationNotificationRefreshes = 0;
    await pump(
      tester,
      _FakeBattery(exempt: true),
      onTestNotification:
          ({required title, required body, required preferences}) async {
            testedTitles.add(title);
            testedBodies.add(body);
            testedPreferences.add(preferences);
          },
      onTestBackgroundLocation: ({required title, required body}) async {
        backgroundTests.add((title: title, body: body));
      },
      onNotificationSettingsChanged: () async {
        locationNotificationRefreshes++;
      },
    );
    tester.view.physicalSize = const Size(1080, 10000);
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
    expect(find.text('Notification settings'), findsOneWidget);
    expect(find.byKey(const Key('notification-type-messages')), findsOneWidget);
    expect(
      find.byKey(const Key('notification-type-ring-requests')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('notification-type-background-location')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('notification-type-messages')));
    await tester.pumpAndSettle();
    expect(find.text('Chat messages'), findsOneWidget);
    expect(find.text('Follow system'), findsOneWidget);
    expect(find.text('Use app settings'), findsOneWidget);
    expect(await settings.getIncomingChatAlertTitle(), isEmpty);
    expect(await settings.getIncomingChatAlertText(), isEmpty);
    await tester.tap(find.text('Use app settings'));
    await tester.pumpAndSettle();
    expect(
      (await settings.getIncomingChatAlertPreferences()).source,
      NotificationAlertSource.system,
    );
    await tester.tap(find.text('Vibrate').first);
    await tester.pumpAndSettle();
    expect(
      (await settings.getIncomingChatAlertPreferences()).vibrationEnabled,
      isTrue,
    );
    await tester.tap(find.text('Vibrate').first);
    await tester.pumpAndSettle();
    expect(find.text('Vibration pattern'), findsOneWidget);
    await tester.tap(find.byKey(const Key('incoming-chat-vibration-pattern')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Short pulses').last);
    await tester.pumpAndSettle();
    expect(
      (await settings.getIncomingChatAlertPreferences()).vibrationPattern,
      IncomingChatVibrationPattern.standard,
    );

    await tester.ensureVisible(
      find.byKey(const Key('incoming-chat-title-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incoming-chat-title-field')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('incoming-chat-title-field')),
      'P',
    );
    await tester.pump();
    final headerEditable = find.descendant(
      of: find.byKey(const Key('incoming-chat-title-field')),
      matching: find.byType(EditableText),
    );
    expect(
      tester.widget<EditableText>(headerEditable).focusNode.hasFocus,
      isTrue,
    );
    await tester.enterText(
      find.byKey(const Key('incoming-chat-title-field')),
      'Private chat',
    );
    await tester.ensureVisible(
      find.byKey(const Key('incoming-chat-message-field')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('incoming-chat-message-field')));
    await tester.enterText(
      find.byKey(const Key('incoming-chat-message-field')),
      'A message is waiting',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('incoming-chat-message-field')),
          )
          .controller!
          .text,
      'A message is waiting',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(await settings.getIncomingChatAlertTitle(), isEmpty);
    expect(await settings.getIncomingChatAlertText(), isEmpty);

    await tester.ensureVisible(
      find.byKey(const Key('test-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('test-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(testedTitles, ['Private chat']);
    expect(testedBodies, ['A message is waiting']);
    expect(testedPreferences.single.source, NotificationAlertSource.custom);
    expect(testedPreferences.single.vibrationEnabled, isTrue);
    expect(
      testedPreferences.single.vibrationPattern,
      IncomingChatVibrationPattern.shortPulses,
    );
    expect(await settings.getIncomingChatAlertTitle(), isEmpty);
    expect(await settings.getIncomingChatAlertText(), isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('save-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(await settings.getIncomingChatAlertTitle(), 'Private chat');
    expect(await settings.getIncomingChatAlertText(), 'A message is waiting');
    expect(
      (await settings.getIncomingChatAlertPreferences()).source,
      NotificationAlertSource.custom,
    );
    expect(
      (await settings.getIncomingChatAlertPreferences()).vibrationPattern,
      IncomingChatVibrationPattern.shortPulses,
    );

    await tester.enterText(
      find.byKey(const Key('incoming-chat-title-field')),
      'Unsaved change',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('revert-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('incoming-chat-title-field')))
          .controller!
          .text,
      'Private chat',
    );

    await tester.ensureVisible(
      find.byKey(const Key('reset-incoming-chat-notification-button')),
    );
    await tester.tap(
      find.byKey(const Key('reset-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(await settings.getIncomingChatAlertTitle(), 'Private chat');
    expect(await settings.getIncomingChatAlertText(), 'A message is waiting');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('save-incoming-chat-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(await settings.getIncomingChatAlertTitle(), isEmpty);
    expect(await settings.getIncomingChatAlertText(), isEmpty);
    expect(
      (await settings.getIncomingChatAlertPreferences()).source,
      NotificationAlertSource.system,
    );
    expect(
      (await settings.getIncomingChatAlertPreferences()).vibrationPattern,
      IncomingChatVibrationPattern.standard,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notification-type-background-location')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Background location'), findsOneWidget);
    expect(await settings.getBackgroundLocationAlertTitle(), isEmpty);
    expect(await settings.getBackgroundLocationAlertText(), isEmpty);
    await tester.ensureVisible(
      find.byKey(const Key('background-location-title-field')),
    );
    await tester.tap(find.byKey(const Key('background-location-title-field')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('background-location-title-field')),
      'Location',
    );
    await tester.ensureVisible(
      find.byKey(const Key('background-location-message-field')),
    );
    await tester.tap(
      find.byKey(const Key('background-location-message-field')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('background-location-message-field')),
      'Sharing is active',
    );
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('background-location-message-field')),
          )
          .controller!
          .text,
      'Sharing is active',
    );
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pumpAndSettle();
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    expect(await settings.getBackgroundLocationAlertTitle(), isEmpty);
    expect(await settings.getBackgroundLocationAlertText(), isEmpty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('test-background-location-notification-button')),
    );
    await tester.tap(
      find.byKey(const Key('test-background-location-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(backgroundTests, [(title: 'Location', body: 'Sharing is active')]);
    expect(await settings.getBackgroundLocationAlertText(), isEmpty);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('save-background-location-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(await settings.getBackgroundLocationAlertTitle(), 'Location');
    expect(
      await settings.getBackgroundLocationAlertText(),
      'Sharing is active',
    );
    expect(locationNotificationRefreshes, greaterThan(0));

    await tester.enterText(
      find.byKey(const Key('background-location-message-field')),
      'Unsaved change',
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const Key('revert-background-location-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('background-location-message-field')),
          )
          .controller!
          .text,
      'Sharing is active',
    );

    await tester.ensureVisible(
      find.byKey(const Key('reset-background-location-notification-button')),
    );
    await tester.tap(
      find.byKey(const Key('reset-background-location-notification-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();
    expect(
      await settings.getBackgroundLocationAlertText(),
      'Sharing is active',
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('save-background-location-notification-button')),
    );
    await tester.pumpAndSettle();
    expect(await settings.getBackgroundLocationAlertTitle(), isEmpty);
    expect(await settings.getBackgroundLocationAlertText(), isEmpty);
    expect(locationNotificationRefreshes, greaterThan(1));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('notification-settings-navigation-tile')),
      findsOneWidget,
    );
  });

  testWidgets('ring settings open as a configuration route from the selector', (
    tester,
  ) async {
    await pump(tester, _FakeBattery(exempt: true));
    tester.view.physicalSize = const Size(1080, 7000);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const Key('notification-settings-navigation-tile')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('notification-type-ring-requests')));
    await tester.pumpAndSettle();

    expect(
      find.text('Ring requests are currently available on Android.'),
      findsOneWidget,
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('notification-type-messages')), findsOneWidget);
  });

  testWidgets('Settings Back returns to the screen that opened it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (context, state) => BaseScreenShell(
            title: 'Chat',
            showQuickLock: false,
            drawerSelectedIndex: 0,
            body: const Center(child: Text('Chat previous screen')),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => BaseScreenShell(
            title: 'Settings',
            showDrawerMenu: false,
            showQuickLock: false,
            body: const Center(child: Text('Settings screen')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Settings screen'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Chat previous screen'), findsOneWidget);
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

  testWidgets('opening Settings from Chat preserves Back navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (context, state) => BaseScreenShell(
            title: 'Chat',
            showQuickLock: false,
            drawerSelectedIndex: 0,
            body: const Center(child: Text('Chat previous screen')),
          ),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => BaseScreenShell(
            title: 'Settings',
            showDrawerMenu: false,
            showQuickLock: false,
            drawerSelectedIndex: 6,
            body: const Center(child: Text('Settings screen')),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').last);
    await tester.pumpAndSettle();
    expect(find.text('Settings screen'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Chat previous screen'), findsOneWidget);
  });

  testWidgets('standalone Photo sync toggle is removed and auto-lock delay disables when auto-lock is off', (
    tester,
  ) async {
    await pump(tester, _FakeBattery(exempt: true));

    expect(find.text('Photo sync'), findsNothing);

    final dropdownFinder = find.byKey(const Key('auto-lock-timeout-dropdown'));
    expect(
      tester.widget<DropdownButton<int>>(dropdownFinder).onChanged,
      isNotNull,
    );

    await tester.tap(find.text('Auto-lock on background'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<DropdownButton<int>>(dropdownFinder).onChanged,
      isNull,
    );
  });
}
