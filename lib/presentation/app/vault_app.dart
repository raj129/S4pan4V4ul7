import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../application/services/import_manager.dart';
import '../../application/services/restore_flow_service.dart';
import '../../application/services/pin_validator.dart';
import '../../application/services/vault_session.dart';
import '../../application/usecases/create_vault_usecase.dart';
import '../../application/usecases/unlock_vault_usecase.dart';
import '../../crypto/services/aes_gcm_crypto_service.dart';
import '../../data/repositories_impl/in_memory_auth_repository.dart';
import '../../data/repositories_impl/flutter_secure_string_kv.dart';
import '../../data/repositories_impl/in_memory_photo_repository.dart';
import '../../data/repositories_impl/in_memory_secure_storage_repository.dart';
import '../../data/repositories_impl/in_memory_settings_repository.dart';
import '../../data/repositories_impl/in_memory_vault_repository.dart';
import '../../data/repositories_impl/persistent_photo_repository.dart';
import '../../data/repositories_impl/persistent_settings_repository.dart';
import '../../data/repositories_impl/persistent_vault_repository.dart';
import '../../data/repositories_impl/secure_storage_flutter_repository.dart';
import '../../data/services/pbkdf2_kdf_service.dart';
import '../../data/services/local_auth_biometric_service.dart';
import '../../data/services/stub_restore_flow_service.dart';
import '../../domain/entities/user_mode.dart';
import '../../domain/entities/vault_photo.dart';
import '../../domain/entities/vault_status.dart';
import '../screens/gallery/gallery_home_screen.dart';
import '../screens/gallery/gallery_photo_viewer_screen.dart';
import '../screens/import/import_screen.dart';
import '../screens/lock/lock_screen.dart';
import '../screens/onboarding/biometric_setup_screen.dart';
import '../screens/onboarding/google_signin_screen.dart';
import '../screens/onboarding/pin_screens.dart';
import '../screens/onboarding/vault_creation_screen.dart';
import '../screens/onboarding/welcome_screen.dart';
import '../screens/restore/restore_flow_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../state/onboarding/onboarding_cubit.dart';
import '../state/onboarding/onboarding_state.dart';

/// App root: wires all dependencies and configures go_router.
///
/// Production: replace in-memory/stub implementations with real
/// Drift DB, FlutterSecureStorage, FirebaseAuthRepository, and
/// LocalAuthBiometricService once available.
class VaultApp extends StatefulWidget {
  const VaultApp({super.key, this.persistentState = true});

  final bool persistentState;

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> with WidgetsBindingObserver {
  static const _defaultSecureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  late final _vaultRepository = widget.persistentState
      ? PersistentVaultRepository(FlutterSecureStringKv(_defaultSecureStorage))
      : InMemoryVaultRepository();
  late final _secureStorageRepository = widget.persistentState
      ? SecureStorageFlutterRepository(_defaultSecureStorage)
      : InMemorySecureStorageRepository();
  late final _settingsRepository = widget.persistentState
      ? PersistentSettingsRepository(
          FlutterSecureStringKv(_defaultSecureStorage),
        )
      : InMemorySettingsRepository();
  late final _photoRepository = widget.persistentState
      ? PersistentPhotoRepositoryImpl()
      : InMemoryPhotoRepository();
  final _authRepository = InMemoryAuthRepository();
  final _cryptoService = AesGcmCryptoService();
  final _kdfService = Pbkdf2KdfService();
  final _vaultSession = VaultSession();
  final _biometricService = LocalAuthBiometricService();
  final RestoreFlowService _restoreFlowService = const StubRestoreFlowService();
  final _pinValidator = PinValidator();
  late final ImportManager _importManager;

  late final CreateVaultUseCase _createVaultUseCase;
  late final UnlockVaultUseCase _unlockVaultUseCase;
  late final OnboardingCubit _onboardingCubit;
  late final GoRouter _router;
  StreamSubscription<List<SharedMediaFile>>? _shareStreamSub;
  UserMode _lastKnownMode = UserMode.localOnly;
  bool _biometricUnlockEnabled = false;
  bool _photoSyncEnabled = false;
  final ValueNotifier<bool> _sessionUnlocked = ValueNotifier<bool>(false);
  Timer? _backgroundLockTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _createVaultUseCase = CreateVaultUseCase(
      cryptoService: _cryptoService,
      kdfService: _kdfService,
      vaultRepository: _vaultRepository,
      secureStorageRepository: _secureStorageRepository,
      vaultSession: _vaultSession,
    );
    _unlockVaultUseCase = UnlockVaultUseCase(
      vaultRepository: _vaultRepository,
      secureStorageRepository: _secureStorageRepository,
      kdfService: _kdfService,
      cryptoService: _cryptoService,
      vaultSession: _vaultSession,
    );
    _importManager = ImportManager(
      photoRepository: _photoRepository,
      cryptoService: _cryptoService,
      vaultSession: _vaultSession,
    );
    _onboardingCubit = OnboardingCubit(
      authRepository: _authRepository,
      biometricService: _biometricService,
      createVaultUseCase: _createVaultUseCase,
      pinValidator: _pinValidator,
    );
    _router = _buildRouter();
    _initShareIntentHandling();
    _initializePhotoRepository();
    _hydrateSessionSettings();
  }

  /// Initialize persistent photo repository if using persistent state.
  Future<void> _initializePhotoRepository() async {
    if (_photoRepository case final PersistentPhotoRepositoryImpl repository) {
      try {
        await repository.initialize();
      } catch (e) {
        debugPrint('❌ Failed to initialize photo repository: $e');
      }
    }
  }

  Future<void> _hydrateSessionSettings() async {
    final mode = await _settingsRepository.getUserMode();
    final biometricEnabled = await _settingsRepository
        .isBiometricUnlockEnabled();
    final photoSyncEnabled = await _settingsRepository.isPhotoSyncEnabled();
    final externalMirrorEnabled = await _settingsRepository
        .isExternalStorageMirrorEnabled();
    final driveEncryptedBackupEnabled = await _settingsRepository
        .isDriveEncryptedBackupEnabled();
    if (!mounted) return;
    setState(() {
      if (mode != null) {
        _lastKnownMode = mode;
      }
      _biometricUnlockEnabled = biometricEnabled;
      _photoSyncEnabled = photoSyncEnabled;
    });
    _importManager.configureStorage(
      useExternalStorageMirror: externalMirrorEnabled,
      driveEncryptedBackupEnabled: driveEncryptedBackupEnabled,
    );
  }

  void _initShareIntentHandling() {
    _shareStreamSub = ReceiveSharingIntent.instance.getMediaStream().listen((
      files,
    ) {
      _handleSharedFiles(files);
    });

    ReceiveSharingIntent.instance.getInitialMedia().then(_handleSharedFiles);
  }

  void _handleSharedFiles(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    final mapped = files
        .where((f) => f.path.isNotEmpty)
        .map((f) => XFile(f.path))
        .toList(growable: false);
    if (mapped.isEmpty) return;
    _importManager.setPendingImportSelection(
      files: mapped,
      source: 'share-intent',
    );
    _router.go('/import/share-intent');
    ReceiveSharingIntent.instance.reset();
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/',
      refreshListenable: _sessionUnlocked,
      redirect: (context, state) async {
        final status = await _vaultRepository.getStatus();
        final loc = state.matchedLocation;
        final isReady = status == VaultStatus.ready;
        final isUnlocked = _sessionUnlocked.value;
        final isLockRoute = loc == '/lock';
        final isOnboarding = loc.startsWith('/onboarding');
        final isRestoreRoute = loc.startsWith('/restore');

        if (!isReady) {
          if (isRestoreRoute || isOnboarding) return null;
          if (loc == '/') return '/onboarding';
          return '/onboarding';
        }

        if (!isUnlocked) {
          if (isLockRoute) return null;
          final encoded = Uri.encodeComponent(loc == '/' ? '/gallery' : loc);
          return '/lock?returnTo=$encoded';
        }

        if (loc == '/' || isLockRoute || isOnboarding) {
          return '/gallery';
        }

        return null;
      },
      routes: [
        GoRoute(path: '/', builder: (_, _) => const SizedBox.shrink()),
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => BlocProvider.value(
            value: _onboardingCubit,
            child: BlocConsumer<OnboardingCubit, OnboardingState>(
              listener: _listener,
              builder: _builder,
            ),
          ),
        ),
        GoRoute(
          path: '/gallery',
          builder: (context, state) {
            final mode = state.extra is UserMode
                ? state.extra as UserMode
                : _lastKnownMode;
            _lastKnownMode = mode;
            return GalleryHomeScreen(
              mode: mode,
              photoRepository: _photoRepository,
              importManager: _importManager,
              photoSyncEnabled: _photoSyncEnabled,
            );
          },
          routes: [
            GoRoute(
              path: 'photo',
              builder: (context, state) {
                final photo = state.extra as VaultPhoto?;
                if (photo == null) {
                  return Scaffold(
                    appBar: AppBar(title: const Text('Error')),
                    body: const Center(child: Text('No photo provided')),
                  );
                }
                return GalleryPhotoViewerScreen(
                  photo: photo,
                  importManager: _importManager,
                  photoRepository: _photoRepository,
                );
              },
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => SettingsScreen(
            mode: _lastKnownMode,
            settingsRepository: _settingsRepository,
            onSettingsChanged: _hydrateSessionSettings,
          ),
        ),
        GoRoute(
          path: '/lock',
          builder: (context, state) {
            final returnTo = state.uri.queryParameters['returnTo'];
            final decodedReturnTo = returnTo == null
                ? '/gallery'
                : Uri.decodeComponent(returnTo);
            return LockScreen(
              unlockVaultUseCase: _unlockVaultUseCase,
              pinValidator: _pinValidator,
              biometricService: _biometricService,
              biometricEnabled: _biometricUnlockEnabled,
              onUnlocked: () {
                _sessionUnlocked.value = true;
                unawaited(_importManager.reconcileVaultFiles());
                final importTarget = _importManager.hasPendingShareFiles
                    ? '/import/share-intent'
                    : null;
                context.go(importTarget ?? decodedReturnTo);
              },
            );
          },
        ),
        GoRoute(
          path: '/restore',
          builder: (context, state) => RestoreFlowScreen(
            authRepository: _authRepository,
            restoreFlowService: _restoreFlowService,
            onRestoreCompleted: (pin, includePhotos) async {
              await _createVaultUseCase.execute(
                pin: pin,
                mode: UserMode.googleEnabled,
                biometricEnabled: false,
              );
              _lastKnownMode = UserMode.googleEnabled;
              await _settingsRepository.saveUserMode(UserMode.googleEnabled);
              await _settingsRepository.setPhotoSyncEnabled(includePhotos);
              _photoSyncEnabled = includePhotos;
              _sessionUnlocked.value = true;
              if (!context.mounted) return;
              context.go('/gallery', extra: UserMode.googleEnabled);
            },
          ),
        ),
        GoRoute(
          path: '/import',
          builder: (context, state) => ImportBottomSheetLauncherScreen(
            importManager: _importManager,
            onClosed: () => context.go('/gallery', extra: _lastKnownMode),
          ),
        ),
        GoRoute(
          path: '/import/share-intent',
          builder: (context, state) => ImportBottomSheetLauncherScreen(
            importManager: _importManager,
            autoOpenShareReview: true,
            onClosed: () => context.go('/gallery', extra: _lastKnownMode),
          ),
        ),
      ],
    );
  }

  void _listener(BuildContext context, OnboardingState state) {
    if (state is OnboardingVaultCreated) {
      _lastKnownMode = state.mode;
      unawaited(_settingsRepository.saveUserMode(state.mode));
      unawaited(_hydrateSessionSettings());
      _sessionUnlocked.value = true;
      context.go('/gallery', extra: state.mode);
    }
  }

  Widget _builder(BuildContext context, OnboardingState state) {
    return switch (state) {
      OnboardingInitial() => const WelcomeScreen(),
      OnboardingModeSelectedLocal() => const WelcomeScreen(),
      OnboardingGoogleSignInInProgress() => const GoogleSignInScreen(),
      OnboardingGoogleSignInSuccess() => const GoogleSignInScreen(),
      OnboardingGoogleSignInFailed() => const GoogleSignInScreen(),
      OnboardingPinEntry(mode: final m) => CreatePinScreen(mode: m),
      OnboardingPinConfirm(mode: final m) => ConfirmPinScreen(mode: m),
      OnboardingPinInvalid(mode: final m) => CreatePinScreen(mode: m),
      OnboardingBiometricCheck() => const WelcomeScreen(),
      OnboardingBiometricAvailable(mode: final m, availability: final a) =>
        BiometricSetupScreen(mode: m, availability: a),
      OnboardingBiometricEnabled(mode: final m) => VaultCreationScreen(mode: m),
      OnboardingBiometricSkipped(mode: final m) => VaultCreationScreen(mode: m),
      OnboardingCreatingVault(mode: final m) => VaultCreationScreen(mode: m),
      OnboardingVaultCreated() => const SizedBox.shrink(),
      OnboardingError() => const WelcomeScreen(),
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_sessionUnlocked.value) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.inactive) {
      _backgroundLockTimer?.cancel();
      _backgroundLockTimer = Timer(const Duration(seconds: 10), _lockSession);
      return;
    }
    if (state == AppLifecycleState.resumed) {
      _backgroundLockTimer?.cancel();
    }
  }

  void _lockSession() {
    _vaultSession.lock();
    _sessionUnlocked.value = false;
    final location = _router.routerDelegate.currentConfiguration.uri.toString();
    final encoded = Uri.encodeComponent(
      location.isEmpty ? '/gallery' : location,
    );
    _router.go('/lock?returnTo=$encoded');
  }

  @override
  void dispose() {
    _onboardingCubit.close();
    _shareStreamSub?.cancel();
    _backgroundLockTimer?.cancel();
    _vaultSession.lock();
    _closePhotoRepository();
    WidgetsBinding.instance.removeObserver(this);
    _sessionUnlocked.dispose();
    super.dispose();
  }

  /// Close persistent photo repository if using persistent state.
  void _closePhotoRepository() {
    if (_photoRepository case final PersistentPhotoRepositoryImpl repository) {
      repository.close().ignore();
    }
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
