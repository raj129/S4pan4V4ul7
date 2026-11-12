import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import './app_session.dart';
import './external_activity_guard.dart';
import './android_chat_viewer_guard.dart';
import '../di/app_dependencies.dart';
import '../location/presentation/mock_location_banner.dart';
import '../media/animated_media.dart';
import '../platform/hdr_preview_capability.dart';
import '../platform/screenshot_protection.dart';
import '../routing/app_router.dart';
import '../widgets/app_navigation_drawer.dart';
import '../../features/vault/presentation/state/onboarding_cubit.dart';
import '../../features/vault/domain/repositories/settings_repository.dart';
import '../presentation/theme/app_colors.dart';
import '../presentation/theme/app_theme.dart';
import '../../features/chat/application/services/chat_notification_service.dart';

/// App root: owns the dependency container, session state, and router.
///
/// Construction of individual repositories/services/use cases now lives in
/// [AppDependencies], and the route table/redirect logic lives in
/// [buildAppRouter]. This widget is left with only what genuinely needs to
/// be a `State`: lifecycle-driven auto-lock, share-intent plumbing, and
/// wiring the router/session/dependencies together.
class VaultApp extends StatefulWidget {
  const VaultApp({super.key, this.persistentState = true});

  final bool persistentState;

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> with WidgetsBindingObserver {
  late final AppDependencies _deps = AppDependencies(
    persistentState: widget.persistentState,
  );
  final AppSessionState _session = AppSessionState();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
  late final ChatNotificationService _notificationService =
      _deps.chatDependencies.notificationService;
  late final OnboardingCubit _onboardingCubit = OnboardingCubit(
    authRepository: _deps.authRepository,
    createVaultUseCase: _deps.createVaultUseCase,
    pinValidator: _deps.pinValidator,
    restoreFlowService: _deps.restoreFlowService,
  );
  late final GoRouter _router = buildAppRouter(
    deps: _deps,
    session: _session,
    onboardingCubit: _onboardingCubit,
    onSettingsChanged: _hydrateSessionSettings,
  );

  StreamSubscription<List<SharedMediaFile>>? _shareStreamSub;
  Timer? _backgroundLockTimer;
  AppThemePalette _themePalette = AppThemePalette.royalIndigo;
  ThemeMode _themeMode = ThemeMode.system;
  bool _autoLockOnBackground = true;
  int _autoLockTimeoutSeconds =
      SettingsRepository.defaultAutoLockTimeoutSeconds;
  final ScreenshotProtectionController _screenshotProtection =
      const AndroidScreenshotProtection();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _notificationService.foregroundNotification.addListener(
      _showForegroundNotification,
    );
    _router.routeInformationProvider.addListener(_updateChatVisibility);
    _updateChatVisibility();
    HdrPreviewPreference.instance.configure(_deps.settingsRepository);
    unawaited(HdrPreviewCapability.instance.load());
    _initShareIntentHandling();
    // Database/storage setup failing must not be silent: report it (to
    // Crashlytics in release via FlutterError.onError) instead of leaving the
    // app running against a half-initialised store.
    unawaited(
      _deps.initialize().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'app initialisation',
          ),
        );
      }),
    );
    unawaited(_hydrateSessionSettings());
  }

  void _updateChatVisibility() {
    final path = _router.routeInformationProvider.value.uri.path;
    _notificationService.setChatSectionVisible(
      path == '/chat' || path == '/chat/thread',
    );
  }

  void _showForegroundNotification() {
    final notification = _notificationService.foregroundNotification.value;
    final messenger = _scaffoldMessengerKey.currentState;
    if (notification == null || messenger == null) return;

    messenger
      ..hideCurrentMaterialBanner()
      ..showMaterialBanner(
        MaterialBanner(
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                notification.title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              if (notification.body.isNotEmpty) Text(notification.body),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _router.go('/chat');
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    _notificationService.openFromNotification(
                      notification.threadId,
                    );
                  }
                });
                messenger.hideCurrentMaterialBanner();
              },
              child: const Text('Open'),
            ),
            TextButton(
              onPressed: messenger.hideCurrentMaterialBanner,
              child: const Text('Dismiss'),
            ),
          ],
        ),
      );
  }

  Future<void> _hydrateSessionSettings() async {
    final mode = await _deps.settingsRepository.getUserMode();
    final calculatorOnboardingCompleted = await _deps.settingsRepository
        .isCalculatorOnboardingCompleted();
    final photoSyncEnabled = await _deps.settingsRepository
        .isPhotoSyncEnabled();
    final externalMirrorEnabled = await _deps.settingsRepository
        .isExternalStorageMirrorEnabled();
    final driveEncryptedBackupEnabled = await _deps.settingsRepository
        .isDriveEncryptedBackupEnabled();
    final autoLockOnBackground = await _deps.settingsRepository
        .isAutoLockOnBackgroundEnabled();
    final autoLockTimeoutSeconds = await _deps.settingsRepository
        .getAutoLockTimeoutSeconds();
    final screenshotProtectionEnabled = await _deps.settingsRepository
        .isScreenshotProtectionEnabled();
    if (_screenshotProtection.isSupportedPlatform) {
      try {
        await _screenshotProtection.setEnabled(screenshotProtectionEnabled);
      } catch (error, stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            library: 'screenshot protection',
          ),
        );
      }
    }
    final paletteId = await _deps.settingsRepository.getThemePaletteId();
    final rawThemeMode = await _deps.settingsRepository.getThemeMode();
    if (!mounted) return;
    if (mode != null) _session.mode = mode;
    _session.calculatorOnboardingCompleted = calculatorOnboardingCompleted;
    _session.photoSyncEnabled = photoSyncEnabled;
    _deps.importManager.configureStorage(
      useExternalStorageMirror: externalMirrorEnabled,
      driveEncryptedBackupEnabled: driveEncryptedBackupEnabled,
    );
    final nextPalette = AppThemePalette.fromId(paletteId);
    final nextThemeMode = switch (rawThemeMode) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    if (_themePalette != nextPalette ||
        _themeMode != nextThemeMode ||
        _autoLockOnBackground != autoLockOnBackground ||
        _autoLockTimeoutSeconds != autoLockTimeoutSeconds) {
      setState(() {
        _themePalette = nextPalette;
        _themeMode = nextThemeMode;
        _autoLockOnBackground = autoLockOnBackground;
        _autoLockTimeoutSeconds = autoLockTimeoutSeconds;
      });
    }
  }

  void _initShareIntentHandling() {
    _shareStreamSub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleSharedFiles,
    );
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then(_handleSharedFiles)
        .catchError((_) {})
        .ignore();
  }

  Future<void> _handleSharedFiles(List<SharedMediaFile> files) async {
    if (files.isEmpty) return;
    final mapped = files
        .where((f) => f.path.isNotEmpty)
        .map((f) => XFile(f.path))
        .toList(growable: false);
    if (mapped.isEmpty) return;
    _deps.importManager.setPendingShareFiles(mapped);
    // On a cold start the router is still resolving its initial location;
    // navigating before then is overwritten and leaves a blank screen.
    for (var i = 0; i < 100; i++) {
      if (_router.routerDelegate.currentConfiguration.isNotEmpty) break;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return;
    }
    _router.go('/');
    unawaited(ReceiveSharingIntent.instance.reset());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_session.isUnlocked || !_autoLockOnBackground) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _backgroundLockTimer?.cancel();
      if (defaultTargetPlatform == TargetPlatform.android &&
          AndroidChatViewerGuard.suppressesLock(state)) {
        return;
      }
      if (ExternalActivityGuard.isActive) return;
      _backgroundLockTimer = Timer(
        Duration(seconds: _autoLockTimeoutSeconds),
        () {
          if (ExternalActivityGuard.isActive) return;
          _lockSession();
        },
      );
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _backgroundLockTimer?.cancel();
    }
  }

  void _lockSession() {
    _deps.vaultSession.lock();
    _session.lock();
    if (!mounted) return;
    _router.go('/');
  }

  @override
  void dispose() {
    _onboardingCubit.close();
    _shareStreamSub?.cancel();
    _backgroundLockTimer?.cancel();
    _notificationService.foregroundNotification.removeListener(
      _showForegroundNotification,
    );
    _router.routeInformationProvider.removeListener(_updateChatVisibility);
    unawaited(_deps.dispose());
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Calculator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.forPalette(_themePalette, Brightness.light),
      darkTheme: AppTheme.forPalette(_themePalette, Brightness.dark),
      themeMode: _themeMode,
      routerConfig: _router,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      builder: (context, child) => AppDrawerScope(
        hasMyLocations: () =>
            Platform.isAndroid &&
            _deps.chatDependencies.authService.currentUid != null,
        child: MockLocationBanner(
          controller: _deps.location.mock,
          visibilityListenable: _session,
          isVisible: () => _session.isUnlocked,
          onOpen: () => _router.push('/settings/developer'),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
