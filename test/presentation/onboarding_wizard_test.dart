import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/core/data/repositories/stub_auth_repository.dart';
import 'package:photo_vault/core/session/vault_session.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_secure_storage_repository.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_vault_repository.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import 'package:photo_vault/features/vault/application/services/onboarding_restore_bridge.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/create_vault_usecase.dart';
import 'package:photo_vault/features/vault/data/services/pbkdf2_kdf_service.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/presentation/screens/onboarding/onboarding_restore_screen.dart';
import 'package:photo_vault/features/vault/presentation/screens/onboarding/onboarding_wizard_header.dart';
import 'package:photo_vault/features/vault/presentation/screens/onboarding/pin_screens.dart';
import 'package:photo_vault/features/vault/presentation/screens/onboarding/welcome_screen.dart';
import 'package:photo_vault/features/vault/presentation/state/onboarding_cubit.dart';
import 'package:photo_vault/features/vault/presentation/state/onboarding_state.dart';

OnboardingCubit _makeTestCubit({OnboardingState? initialState}) {
  final cubit = OnboardingCubit(
    authRepository: const StubAuthRepository(),
    createVaultUseCase: CreateVaultUseCase(
      cryptoService: AesGcmCryptoService(),
      kdfService: Pbkdf2KdfService(iterations: 1000),
      vaultRepository: InMemoryVaultRepository(),
      secureStorageRepository: InMemorySecureStorageRepository(),
      vaultSession: VaultSession(),
      backupRepositories: const [],
    ),
    pinValidator: PinValidator(),
  );
  if (initialState != null) {
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    cubit.emit(initialState);
  }
  return cubit;
}

void main() {
  testWidgets('WelcomeScreen shows Step 1 of 4 and Gmail primary CTA', (
    tester,
  ) async {
    final cubit = _makeTestCubit();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const WelcomeScreen(),
        ),
      ),
    );

    expect(find.textContaining('Step 1 of 4'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Continue locally'), findsOneWidget);
    expect(find.byType(OnboardingWizardHeader), findsOneWidget);
  });

  testWidgets('CreatePinScreen shows Step 2 of 4 and ConfirmPinScreen Step 3 of 4', (
    tester,
  ) async {
    final cubit = _makeTestCubit();
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const CreatePinScreen(mode: UserMode.googleEnabled),
        ),
      ),
    );
    expect(find.textContaining('Step 2 of 4'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const ConfirmPinScreen(mode: UserMode.googleEnabled),
        ),
      ),
    );
    expect(find.textContaining('Step 3 of 4'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });

  testWidgets('OnboardingRestoreScreen shows Step 4 of 4, old PIN field, and chat progress', (
    tester,
  ) async {
    final cubit = _makeTestCubit(
      initialState: const OnboardingRestoreAvailable(
        mode: UserMode.googleEnabled,
        discovery: OnboardingBackupDiscovery(
          localVaultId: 'v1',
          cloudVaultId: 'v1',
        ),
        selectedSource: OnboardingRestoreSource.googleDrive,
        needsOldPin: true,
        errorMessage: 'Previous PIN required.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: const OnboardingRestoreScreen(),
        ),
      ),
    );

    expect(find.textContaining('Step 4 of 4'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Google Drive'), findsOneWidget);
    expect(find.text('This device (Local)'), findsOneWidget);
    expect(find.text('Restore chat'), findsOneWidget);
    expect(find.text('Restore vault'), findsOneWidget);
    expect(find.text('Restore vault photos'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -350));
    await tester.pumpAndSettle();
    expect(find.text('Previous 4-digit PIN'), findsOneWidget);
    expect(find.text('Unlock & restore'), findsOneWidget);

    // Transition to live chat restore progress
    // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
    cubit.emit(
      const OnboardingRestoringBackup(
        mode: UserMode.googleEnabled,
        source: OnboardingRestoreSource.googleDrive,
        chatProgress: ChatRestoreProgress(
          stage: ChatRestoreStage.restoringMessages,
          source: 'Google Drive',
          done: 25,
          total: 100,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Restoring your backups…'), findsOneWidget);
    expect(find.text('Restoring messages (25 of 100)…'), findsOneWidget);
  });
}
