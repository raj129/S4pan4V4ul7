import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/application/services/pin_validator.dart';
import 'package:photo_vault/application/services/vault_session.dart';
import 'package:photo_vault/application/usecases/create_vault_usecase.dart';
import 'package:photo_vault/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/data/repositories_impl/in_memory_secure_storage_repository.dart';
import 'package:photo_vault/data/repositories_impl/in_memory_vault_repository.dart';
import 'package:photo_vault/data/repositories_impl/stub_auth_repository.dart';
import 'package:photo_vault/data/services/pbkdf2_kdf_service.dart';
import 'package:photo_vault/data/services/stub_biometric_service.dart';
import 'package:photo_vault/domain/entities/user_mode.dart';
import 'package:photo_vault/presentation/state/onboarding/onboarding_cubit.dart';
import 'package:photo_vault/presentation/state/onboarding/onboarding_state.dart';

OnboardingCubit _makeCubit() {
  final vaultRepo = InMemoryVaultRepository();
  final secureRepo = InMemorySecureStorageRepository();
  return OnboardingCubit(
    authRepository: const StubAuthRepository(),
    biometricService: const StubBiometricService(),
    createVaultUseCase: CreateVaultUseCase(
      cryptoService: AesGcmCryptoService(),
      kdfService: Pbkdf2KdfService(iterations: 1000),
      vaultRepository: vaultRepo,
      secureStorageRepository: secureRepo,
      vaultSession: VaultSession(),
    ),
    pinValidator: PinValidator(),
  );
}

void main() {
  group('OnboardingCubit — local mode path', () {
    blocTest<OnboardingCubit, OnboardingState>(
      'selectLocalMode emits PinEntry(localOnly)',
      build: _makeCubit,
      act: (cubit) => cubit.selectLocalMode(),
      expect: () => [
        const OnboardingModeSelectedLocal(),
        const OnboardingPinEntry(mode: UserMode.localOnly),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'pinEntered with weak PIN emits PinInvalid',
      build: _makeCubit,
      act: (cubit) {
        cubit.selectLocalMode();
        cubit.pinEntered(UserMode.localOnly, '123456');
      },
      expect: () => [
        const OnboardingModeSelectedLocal(),
        const OnboardingPinEntry(mode: UserMode.localOnly),
        isA<OnboardingPinInvalid>().having(
          (s) => s.mode,
          'mode',
          UserMode.localOnly,
        ),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'pinEntered with valid PIN emits PinConfirm',
      build: _makeCubit,
      act: (cubit) {
        cubit.selectLocalMode();
        cubit.pinEntered(UserMode.localOnly, '847291');
      },
      expect: () => [
        const OnboardingModeSelectedLocal(),
        const OnboardingPinEntry(mode: UserMode.localOnly),
        const OnboardingPinConfirm(mode: UserMode.localOnly),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'confirm mismatch emits PinInvalid',
      build: _makeCubit,
      act: (cubit) {
        cubit.selectLocalMode();
        cubit.pinEntered(UserMode.localOnly, '847291');
        cubit.pinConfirmed(UserMode.localOnly, '847292'); // wrong
      },
      expect: () => [
        const OnboardingModeSelectedLocal(),
        const OnboardingPinEntry(mode: UserMode.localOnly),
        const OnboardingPinConfirm(mode: UserMode.localOnly),
        isA<OnboardingPinInvalid>(),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'full local flow completes with VaultCreated',
      build: _makeCubit,
      act: (cubit) async {
        cubit.selectLocalMode();
        cubit.pinEntered(UserMode.localOnly, '847291');
        await cubit.pinConfirmed(UserMode.localOnly, '847291');
      },
      expect: () => [
        const OnboardingModeSelectedLocal(),
        const OnboardingPinEntry(mode: UserMode.localOnly),
        const OnboardingPinConfirm(mode: UserMode.localOnly),
        isA<OnboardingBiometricCheck>(),
        isA<OnboardingBiometricSkipped>(),
        isA<OnboardingCreatingVault>().having(
          (s) => s.step,
          'step',
          VaultCreationStep.generatingKeys,
        ),
        isA<OnboardingCreatingVault>().having(
          (s) => s.step,
          'step',
          VaultCreationStep.wrappingVmk,
        ),
        isA<OnboardingCreatingVault>().having(
          (s) => s.step,
          'step',
          VaultCreationStep.done,
        ),
        isA<OnboardingVaultCreated>(),
      ],
    );
  });

  group('OnboardingCubit — Google mode path', () {
    blocTest<OnboardingCubit, OnboardingState>(
      'selectGoogleMode with stub emits GoogleSignInFailed',
      build: _makeCubit,
      act: (cubit) async {
        await cubit.selectGoogleMode();
      },
      expect: () => [
        const OnboardingGoogleSignInInProgress(),
        isA<OnboardingGoogleSignInFailed>(),
      ],
    );

    blocTest<OnboardingCubit, OnboardingState>(
      'fallbackToLocalMode after Google failure advances to PinEntry',
      build: _makeCubit,
      act: (cubit) async {
        await cubit.selectGoogleMode();
        cubit.fallbackToLocalMode();
      },
      expect: () => [
        const OnboardingGoogleSignInInProgress(),
        isA<OnboardingGoogleSignInFailed>(),
        const OnboardingModeSelectedLocal(),
        const OnboardingPinEntry(mode: UserMode.localOnly),
      ],
    );
  });
}
