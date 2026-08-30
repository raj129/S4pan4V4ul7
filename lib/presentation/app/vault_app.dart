import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../core/app/app_session.dart';
import '../../core/di/app_dependencies.dart';
import '../../core/routing/app_router.dart';
import '../state/onboarding/onboarding_cubit.dart';

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
  static const _autoLockDelay = Duration(seconds: 10);

  late final AppDependencies _deps = AppDependencies(
    persistentState: widget.persistentState,
  );
  final AppSessionState _session = AppSessionState();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initShareIntentHandling();
    unawaited(_deps.initialize());
    unawaited(_hydrateSessionSettings());
  }

  Future<void> _hydrateSessionSettings() async {
    final mode = await _deps.settingsRepository.getUserMode();
    final calculatorOnboardingCompleted =
        await _deps.settingsRepository.isCalculatorOnboardingCompleted();
    final photoSyncEnabled = await _deps.settingsRepository.isPhotoSyncEnabled();
    final externalMirrorEnabled =
        await _deps.settingsRepository.isExternalStorageMirrorEnabled();
    final driveEncryptedBackupEnabled =
        await _deps.settingsRepository.isDriveEncryptedBackupEnabled();
    if (!mounted) return;
    if (mode != null) _session.mode = mode;
    _session.calculatorOnboardingCompleted = calculatorOnboardingCompleted;
    _session.photoSyncEnabled = photoSyncEnabled;
    _deps.importManager.configureStorage(
      useExternalStorageMirror: externalMirrorEnabled,
      driveEncryptedBackupEnabled: driveEncryptedBackupEnabled,
    );
  }

  void _initShareIntentHandling() {
    _shareStreamSub = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_handleSharedFiles);
    ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedFiles);
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final mapped = files
        .where((f) => f.path.isNotEmpty)
        .map((f) => XFile(f.path))
        .toList(growable: false);
    if (mapped.isEmpty) return;
    _deps.importManager.setPendingImportSelection(
      files: mapped,
      source: 'share-intent',
    );
    _router.go('/lock?returnTo=%2Fimport%2Fshare-intent');
    ReceiveSharingIntent.instance.reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_session.isUnlocked) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _backgroundLockTimer?.cancel();
      _backgroundLockTimer = Timer(_autoLockDelay, _lockSession);
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _backgroundLockTimer?.cancel();
    }
  }

  void _lockSession() {
    _deps.vaultSession.lock();
    _session.lock();
    final location = _router.routerDelegate.currentConfiguration.uri.toString();
    final encoded = Uri.encodeComponent(location.isEmpty ? '/gallery' : location);
    _router.go('/lock?returnTo=$encoded');
  }

  @override
  void dispose() {
    _onboardingCubit.close();
    _shareStreamSub?.cancel();
    _backgroundLockTimer?.cancel();
    unawaited(_deps.dispose());
    WidgetsBinding.instance.removeObserver(this);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Photo Vault',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A6CF7)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4A6CF7),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
