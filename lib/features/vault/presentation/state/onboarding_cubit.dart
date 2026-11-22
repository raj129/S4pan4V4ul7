import 'package:flutter_bloc/flutter_bloc.dart';

import '../../application/services/onboarding_restore_bridge.dart';
import '../../application/services/pin_validator.dart';
import '../../application/usecases/create_vault_usecase.dart';
import '../../domain/entities/user_mode.dart';
import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'onboarding_state.dart';

/// Drives the first-launch onboarding flow.
///
/// Security invariants:
/// - PIN values are passed through methods but NEVER stored as fields in state.
/// - The cubit never holds VMK bytes; [CreateVaultUseCase] handles that internally.
/// - [_firstPin] is stored only until confirmation/restore then immediately cleared.
class OnboardingCubit extends Cubit<OnboardingState> {
  OnboardingCubit({
    required AuthRepository authRepository,
    required CreateVaultUseCase createVaultUseCase,
    required PinValidator pinValidator,
    OnboardingRestoreBridge? restoreBridge,
  }) : _authRepository = authRepository,
       _createVaultUseCase = createVaultUseCase,
       _pinValidator = pinValidator,
       _restoreBridge = restoreBridge,
       super(const OnboardingInitial());

  final AuthRepository _authRepository;
  final CreateVaultUseCase _createVaultUseCase;
  final PinValidator _pinValidator;
  final OnboardingRestoreBridge? _restoreBridge;

  // Stored only during PIN entry & post-PIN restore; cleared immediately after
  // vault creation/restore. Security: this field is never placed in emitted state.
  String? _firstPin;
  OnboardingBackupDiscovery? _discovery;
  UserMode _currentMode = UserMode.googleEnabled;

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
    _currentMode = mode;
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
      // Keep _firstPin and stay on the confirm step so the user only retypes
      // the confirmation, not the whole PIN.
      emit(
        OnboardingPinConfirm(
          mode: mode,
          errorMessage: "PINs don't match. Try confirming again.",
        ),
      );
      return;
    }
    _currentMode = mode;
    if (_restoreBridge != null) {
      await _checkBackupsAndProceed(mode: mode);
    } else {
      await _createVault(mode: mode);
    }
  }

  // ─────────────────────────────────────────────────
  // Step 3: Post-PIN Backup Discovery & Restore
  // ─────────────────────────────────────────────────

  Future<void> _checkBackupsAndProceed({required UserMode mode}) async {
    final bridge = _restoreBridge;
    if (bridge == null) {
      await _createVault(mode: mode);
      return;
    }
    emit(OnboardingCheckingBackups(mode: mode));
    try {
      final discovery = await bridge.discoverBackups(mode: mode);
      if (!discovery.hasAnyBackup) {
        await _createVault(mode: mode);
        return;
      }
      _discovery = discovery;
      final defaultSource = discovery.hasCloudBackup
          ? OnboardingRestoreSource.googleDrive
          : OnboardingRestoreSource.local;
      emit(
        OnboardingRestoreAvailable(
          mode: mode,
          discovery: discovery,
          selectedSource: defaultSource,
        ),
      );
    } catch (_) {
      await _createVault(mode: mode);
    }
  }

  /// Restores Chat and Vault from [source]. Uses the newly created PIN first;
  /// if [oldPin] is provided (after a mismatch), unwraps with [oldPin] and
  /// re-wraps both Vault VMK and Chat Identity Key under the new PIN.
  Future<void> restoreFromSelectedSource({
    required OnboardingRestoreSource source,
    String? oldPin,
    String? selectedVaultId,
    bool restoreVault = true,
    bool restoreChat = true,
    bool restoreVaultPhotos = true,
  }) async {
    final newPin = _firstPin;
    final discovery = _discovery;
    final bridge = _restoreBridge;
    if (newPin == null || discovery == null || bridge == null) {
      emit(
        const OnboardingError(
          message: 'Session expired. Please restart setup.',
          canRetry: false,
        ),
      );
      return;
    }
    if (oldPin != null) {
      final error = _pinValidator.validate(oldPin);
      if (error != null) {
        emit(
          OnboardingRestoreAvailable(
            mode: _currentMode,
            discovery: discovery,
            selectedSource: source,
            needsOldPin: true,
            errorMessage: error,
          ),
        );
        return;
      }
    }

    emit(
      OnboardingRestoringBackup(
        mode: _currentMode,
        source: source,
        restoreChat: restoreChat,
      ),
    );
    final outcome = await bridge.restoreFromSource(
      source: source,
      discovery: discovery,
      newPin: newPin,
      mode: _currentMode,
      oldPin: oldPin,
      selectedVaultId: selectedVaultId,
      restoreVault: restoreVault,
      restoreChat: restoreChat,
      restoreVaultPhotos: restoreVaultPhotos,
      onChatProgress: (progress) {
        if (!isClosed) {
          emit(
            OnboardingRestoringBackup(
              mode: _currentMode,
              source: source,
              chatProgress: progress,
              restoreChat: restoreChat,
            ),
          );
        }
      },
    );

    switch (outcome) {
      case OnboardingRestoreSuccess(
        :final vaultId,
        :final restoredMessages,
        :final backgroundPhotoRestoreStarted,
      ):
        _firstPin = null;
        _discovery = null;
        emit(
          OnboardingVaultCreated(
            mode: _currentMode,
            vaultId: vaultId,
            restoredMessages: restoredMessages,
            backgroundPhotoRestoreStarted: backgroundPhotoRestoreStarted,
          ),
        );
      case OnboardingRestoreNeedsOldPin(:final message):
        emit(
          OnboardingRestoreAvailable(
            mode: _currentMode,
            discovery: discovery,
            selectedSource: source,
            needsOldPin: true,
            errorMessage: message,
          ),
        );
      case OnboardingRestoreFailure(:final message):
        emit(
          OnboardingRestoreAvailable(
            mode: _currentMode,
            discovery: discovery,
            selectedSource: source,
            needsOldPin: oldPin != null,
            errorMessage: message,
          ),
        );
    }
  }

  /// Skips backup restore and creates a fresh vault using the new PIN.
  Future<void> skipRestoreAndCreateVault() async {
    _discovery = null;
    await _restoreBridge?.dismissChatRestoreOffer();
    await _createVault(mode: _currentMode);
  }

  /// Discards the first PIN and returns to step 1 ("Start over").
  void restartPinEntry(UserMode mode) {
    _firstPin = null;
    emit(OnboardingPinEntry(mode: mode));
  }

  // ─────────────────────────────────────────────────
  // Step 4: Vault creation
  // ─────────────────────────────────────────────────

  Future<void> _createVault({required UserMode mode}) async {
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

      final vaultId = await _createVaultUseCase.execute(pin: pin, mode: mode);

      // Clear PIN from memory immediately after use.
      _firstPin = null;

      emit(OnboardingCreatingVault(mode: mode, step: VaultCreationStep.done));

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
    _discovery = null;
    emit(const OnboardingInitial());
  }
}
