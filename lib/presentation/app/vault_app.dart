import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../application/services/import_manager.dart';
import '../../application/services/pin_validator.dart';
import '../../application/usecases/create_vault_usecase.dart';
import '../../application/usecases/unlock_vault_usecase.dart';
import '../../crypto/services/aes_gcm_crypto_service.dart';
import '../../data/repositories_impl/in_memory_photo_repository.dart';
import '../../data/repositories_impl/in_memory_secure_storage_repository.dart';
import '../../data/repositories_impl/in_memory_vault_repository.dart';
import '../../data/repositories_impl/stub_auth_repository.dart';
import '../../data/services/pbkdf2_kdf_service.dart';
import '../../data/services/stub_biometric_service.dart';
import '../../domain/entities/user_mode.dart';
import '../../domain/entities/vault_status.dart';
import '../screens/gallery/gallery_home_screen.dart';
import '../screens/import/import_screen.dart';
import '../screens/import/import_review_screen.dart';
import '../screens/lock/lock_screen.dart';
import '../screens/onboarding/biometric_setup_screen.dart';
import '../screens/onboarding/google_signin_screen.dart';
import '../screens/onboarding/pin_screens.dart';
import '../screens/onboarding/vault_creation_screen.dart';
import '../screens/onboarding/welcome_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../state/onboarding/onboarding_cubit.dart';
import '../state/onboarding/onboarding_state.dart';

/// App root: wires all dependencies and configures go_router.
///
/// Production: replace in-memory/stub implementations with real
/// Drift DB, FlutterSecureStorage, FirebaseAuthRepository, and
/// LocalAuthBiometricService once available.
class VaultApp extends StatefulWidget {
  const VaultApp({super.key});

  @override
  State<VaultApp> createState() => _VaultAppState();
}

class _VaultAppState extends State<VaultApp> {
  final _vaultRepository = InMemoryVaultRepository();
  final _secureStorageRepository = InMemorySecureStorageRepository();
  final _photoRepository = InMemoryPhotoRepository();
  final _authRepository = const StubAuthRepository();
  final _cryptoService = AesGcmCryptoService();
  final _kdfService = Pbkdf2KdfService();
  final _biometricService = const StubBiometricService();
  final _pinValidator = PinValidator();
  late final ImportManager _importManager;

  late final CreateVaultUseCase _createVaultUseCase;
  late final UnlockVaultUseCase _unlockVaultUseCase;
  late final OnboardingCubit _onboardingCubit;
  late final GoRouter _router;
  StreamSubscription<List<SharedMediaFile>>? _shareStreamSub;
  UserMode _lastKnownMode = UserMode.localOnly;
  final ValueNotifier<bool> _sessionUnlocked = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _createVaultUseCase = CreateVaultUseCase(
      cryptoService: _cryptoService,
      kdfService: _kdfService,
      vaultRepository: _vaultRepository,
      secureStorageRepository: _secureStorageRepository,
    );
    _unlockVaultUseCase = UnlockVaultUseCase(
      vaultRepository: _vaultRepository,
      secureStorageRepository: _secureStorageRepository,
      kdfService: _kdfService,
      cryptoService: _cryptoService,
    );
    _importManager = ImportManager(photoRepository: _photoRepository);
    _onboardingCubit = OnboardingCubit(
      authRepository: _authRepository,
      biometricService: _biometricService,
      createVaultUseCase: _createVaultUseCase,
      pinValidator: _pinValidator,
    );
    _router = _buildRouter();
    _initShareIntentHandling();
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
    _importManager.setPendingShareFiles(mapped);
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

        if (!isReady) {
          if (isOnboarding || loc == '/') return '/onboarding';
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
            );
          },
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => SettingsScreen(mode: _lastKnownMode),
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
              onUnlocked: () {
                _sessionUnlocked.value = true;
                context.go(decodedReturnTo);
              },
            );
          },
        ),
        GoRoute(
          path: '/import',
          builder: (context, state) => ImportScreen(
            importManager: _importManager,
            onOpenReview: (files, source) {
              context.push('/import/review', extra: {
                'files': files,
                'source': source,
              });
            },
          ),
        ),
        GoRoute(
          path: '/import/share-intent',
          builder: (context, state) => ImportScreen(
            importManager: _importManager,
            autoOpenShareReview: true,
            onOpenReview: (files, source) {
              context.push('/import/review', extra: {
                'files': files,
                'source': source,
              });
            },
          ),
        ),
        GoRoute(
          path: '/import/review',
          builder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            final files = (extra?['files'] as List<XFile>?) ?? const <XFile>[];
            final source = (extra?['source'] as String?) ?? 'unknown';
            return ImportReviewScreen(
              files: files,
              source: source,
              importManager: _importManager,
              onImportQueued: () {
                context.go('/gallery', extra: _lastKnownMode);
              },
            );
          },
        ),
      ],
    );
  }

  void _listener(BuildContext context, OnboardingState state) {
    if (state is OnboardingVaultCreated) {
      _lastKnownMode = state.mode;
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
  void dispose() {
    _onboardingCubit.close();
    _shareStreamSub?.cancel();
    _sessionUnlocked.dispose();
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
