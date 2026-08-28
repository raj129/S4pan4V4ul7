import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/services/pin_validator.dart';
import '../../../application/services/restore_flow_service.dart';
import '../../../application/usecases/create_vault_usecase.dart';
import '../../../domain/entities/user_mode.dart';
import '../../../domain/repositories/auth_repository.dart';
import 'onboarding_state.dart';

/// Drives the first-launch onboarding flow.
///
/// Security invariants:
/// - PIN values are passed through methods but NEVER stored as fields.
/// - The cubit never holds VMK bytes; [CreateVaultUseCase] handles that internally.
/// - [_firstPin] is stored only until confirmation then immediately cleared.
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit({
    required AuthRepository authRepository,
    required CreateVaultUseCase createVaultUseCase,
    required PinValidator pinValidator,
    RestoreFlowService? restoreFlowService,
  }) : _authRepository = authRepository,
       _createVaultUseCase = createVaultUseCase,
       _pinValidator = pinValidator,
       _restoreFlowService = restoreFlowService,
       super(const OnboardingInitial());

  final AuthRepository _authRepository;
  final CreateVaultUseCase _createVaultUseCase;
  final PinValidator _pinValidator;
  final RestoreFlowService? _restoreFlowService;

  // Stored only during PIN entry; cleared immediately after vault creation.
  // Security: this field is never placed in emitted state.
  String? _firstPin;

  // ─────────────────────────────────────────────────
  // Step 1: Mode selection
  // ─────────────────────────────────────────────────

  /// User chose to continue locally without Google sign-in.
  void selectLocalMode() {
    _firstPin = null;
    emit(const OnboardingModeSelectedLocal());
    _advanceToPinEntry(UserMode.localOnly);
  }

  /// User chose to sign in with Google.
  Future<void> selectGoogleMode() async {
    _firstPin = null;
    emit(const OnboardingGoogleSignInInProgress());
    try {
      final result = await _authRepository.signInWithGoogle();
      emit(OnboardingGoogleSignInSuccess(email: result.email));
      if (_restoreFlowService != null) {
        try {
          final hasBackup = await _restoreFlowService!.hasBackupManifest();
          if (hasBackup) {
            await _restoreFlowService!.restoreEncryptedVmk();
          }
        } catch (_) {
          // VMK backup not found or restore failed — seamlessly fall back to new vault setup.
        }
      }
      _advanceToPinEntry(UserMode.googleEnabled);
    } on AuthException catch (e) {
      emit(OnboardingGoogleSignInFailed(message: e.message));
    } catch (_) {
      emit(
        const OnboardingGoogleSignInFailed(
          message: 'Sign-in failed. You can continue locally instead.',
        ),
      );
    }
  }

  /// Continue Google-enabled setup as a new vault (no restore).
  void continueGoogleAsNewVault() {
    _advanceToPinEntry(UserMode.googleEnabled);
  }

  /// User cancelled Google sign-in and wants to continue locally.
  void fallbackToLocalMode() {
    emit(const OnboardingModeSelectedLocal());
    _advanceToPinEntry(UserMode.localOnly);
  }

  // ─────────────────────────────────────────────────
  // Step 2: PIN entry
  // ─────────────────────────────────────────────────

  void _advanceToPinEntry(UserMode mode) {
    emit(OnboardingPinEntry(mode: mode));
  }

  /// Called on each digit tap. Updates digit count in state (not digit value).
  void pinDigitChanged(UserMode mode, int digitCount) {
    emit(OnboardingPinEntry(mode: mode, digitCount: digitCount));
  }

  /// Called when the user submits the first PIN.
  void pinEntered(UserMode mode, String pin) {
    final error = _pinValidator.validate(pin);
    if (error != null) {
      emit(OnboardingPinInvalid(mode: mode, message: error));
      return;
    }
    // Store pin temporarily — NEVER emit it in state.
    _firstPin = pin;
    emit(OnboardingPinConfirm(mode: mode));
  }

  /// Called when the user re-enters PIN for confirmation.
  void pinConfirmDigitChanged(UserMode mode, int digitCount) {
    emit(OnboardingPinConfirm(mode: mode, digitCount: digitCount));
  }

  /// Called when the user submits the confirmation PIN.
  Future<void> pinConfirmed(UserMode mode, String confirmPin) async {
    final first = _firstPin;
    if (first == null) {
      // Guard: should never happen in normal flow.
      emit(OnboardingPinEntry(mode: mode));
      return;
    }
    if (!_pinValidator.matches(first, confirmPin)) {
      // Don't clear _firstPin — let user re-confirm.
      emit(
        OnboardingPinInvalid(
          mode: mode,
          message: 'PINs do not match. Please re-enter the confirmation PIN.',
        ),
      );
      return;
    }
    await _createVault(mode: mode);
  }

  // ─────────────────────────────────────────────────
  // Step 4: Vault creation
  // ─────────────────────────────────────────────────

  Future<void> _createVault({
    required UserMode mode,
  }) async {
    final pin = _firstPin;
    if (pin == null) {
      emit(
        const OnboardingError(
          message: 'Session expired. Please restart setup.',
          canRetry: false,
        ),
      );
      return;
    }

    emit(
      OnboardingCreatingVault(
        mode: mode,
        step: VaultCreationStep.generatingKeys,
      ),
    );

    try {
      emit(
        OnboardingCreatingVault(
          mode: mode,
          step: VaultCreationStep.wrappingVmk,
        ),
      );

      final vaultId = await _createVaultUseCase.execute(
        pin: pin,
        mode: mode,
      );

      // Clear PIN from memory immediately after use.
      _firstPin = null;

      emit(
        OnboardingCreatingVault(
          mode: mode,
          step: VaultCreationStep.done,
        ),
      );

      emit(OnboardingVaultCreated(mode: mode, vaultId: vaultId));
    } on VaultCreationException catch (e) {
      _firstPin = null;
      emit(OnboardingError(message: e.message));
    } catch (_) {
      _firstPin = null;
      emit(
        const OnboardingError(
          message: 'An unexpected error occurred during vault creation.',
        ),
      );
    }
  }

  /// Allows retrying from an error state.
  void retry() {
    _firstPin = null;
    emit(const OnboardingInitial());
  }
}
