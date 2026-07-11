import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../application/services/pin_validator.dart';
import '../../application/usecases/create_vault_usecase.dart';
import '../../crypto/services/aes_gcm_crypto_service.dart';
import '../../data/repositories_impl/in_memory_secure_storage_repository.dart';
import '../../data/repositories_impl/in_memory_vault_repository.dart';
import '../../data/repositories_impl/stub_auth_repository.dart';
import '../../data/services/pbkdf2_kdf_service.dart';
import '../../data/services/stub_biometric_service.dart';
import '../../domain/entities/user_mode.dart';
import '../../domain/entities/vault_status.dart';
import '../screens/gallery/gallery_home_screen.dart';
import '../screens/onboarding/biometric_setup_screen.dart';
import '../screens/onboarding/google_signin_screen.dart';
import '../screens/onboarding/pin_screens.dart';
import '../screens/onboarding/vault_creation_screen.dart';
import '../screens/onboarding/welcome_screen.dart';
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
  final _authRepository = const StubAuthRepository();
  final _cryptoService = AesGcmCryptoService();
  final _kdfService = Pbkdf2KdfService();
  final _biometricService = const StubBiometricService();
  final _pinValidator = PinValidator();

  late final CreateVaultUseCase _createVaultUseCase;
  late final OnboardingCubit _onboardingCubit;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _createVaultUseCase = CreateVaultUseCase(
      cryptoService: _cryptoService,
      kdfService: _kdfService,
      vaultRepository: _vaultRepository,
      secureStorageRepository: _secureStorageRepository,
    );
    _onboardingCubit = OnboardingCubit(
      authRepository: _authRepository,
      biometricService: _biometricService,
      createVaultUseCase: _createVaultUseCase,
      pinValidator: _pinValidator,
    );
    _router = _buildRouter();
  }

  GoRouter _buildRouter() {
    return GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          redirect: (context, state) async {
            final status = await _vaultRepository.getStatus();
            return status == VaultStatus.ready ? '/gallery' : '/onboarding';
          },
        ),
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
                : UserMode.localOnly;
            return GalleryHomeScreen(mode: mode);
          },
        ),
      ],
    );
  }

  void _listener(BuildContext context, OnboardingState state) {
    if (state is OnboardingVaultCreated) {
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
