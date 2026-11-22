import 'package:equatable/equatable.dart';

import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import '../../application/services/onboarding_restore_bridge.dart';
import '../../domain/entities/user_mode.dart';

/// Complete state machine for the first-launch onboarding flow.
///
/// States are sealed (all subclasses live in this file) so the UI is
/// forced to handle every state explicitly — no fallthrough.
///
/// Security invariant: NO state subclass ever holds raw VMK bytes,
/// raw DEK bytes, or the plain PIN string after [OnboardingPinConfirm].
sealed class OnboardingState extends Equatable {
  const OnboardingState();
}

/// Initial state — no action taken yet.
final class OnboardingInitial extends OnboardingState {
  const OnboardingInitial();
  @override
  List<Object?> get props => [];
}

/// User chose local-only mode.
final class OnboardingModeSelectedLocal extends OnboardingState {
  const OnboardingModeSelectedLocal();
  @override
  List<Object?> get props => [];
}

/// Google sign-in is in progress.
final class OnboardingGoogleSignInInProgress extends OnboardingState {
  const OnboardingGoogleSignInInProgress();
  @override
  List<Object?> get props => [];
}

/// Google sign-in succeeded.
final class OnboardingGoogleSignInSuccess extends OnboardingState {
  const OnboardingGoogleSignInSuccess({required this.email});
  final String email;
  @override
  List<Object?> get props => [email];
}

/// Google sign-in failed. [message] is user-visible; never log credentials.
final class OnboardingGoogleSignInFailed extends OnboardingState {
  const OnboardingGoogleSignInFailed({required this.message});
  final String message;
  @override
  List<Object?> get props => [message];
}

/// User is entering the first PIN digit sequence.
final class OnboardingPinEntry extends OnboardingState {
  const OnboardingPinEntry({required this.mode, this.digitCount = 0});
  final UserMode mode;

  /// Current number of digits entered (0–6). PIN value is NEVER stored in state.
  final int digitCount;
  @override
  List<Object?> get props => [mode, digitCount];
}

/// User is re-entering PIN for confirmation.
final class OnboardingPinConfirm extends OnboardingState {
  const OnboardingPinConfirm({
    required this.mode,
    this.digitCount = 0,
    this.errorMessage,
  });
  final UserMode mode;
  final int digitCount;

  /// Set when the previous confirmation attempt did not match. The user stays
  /// on the confirm step instead of being bounced back to the first one.
  final String? errorMessage;
  @override
  List<Object?> get props => [mode, digitCount, errorMessage];
}

/// The first PIN was rejected by the validator (e.g. too weak).
final class OnboardingPinInvalid extends OnboardingState {
  const OnboardingPinInvalid({required this.mode, required this.message});
  final UserMode mode;
  final String message;
  @override
  List<Object?> get props => [mode, message];
}

/// Checking Local and Google Drive for existing backups after PIN creation.
final class OnboardingCheckingBackups extends OnboardingState {
  const OnboardingCheckingBackups({required this.mode});
  final UserMode mode;
  @override
  List<Object?> get props => [mode];
}

/// Existing backups were found in Local and/or Google Drive.
final class OnboardingRestoreAvailable extends OnboardingState {
  const OnboardingRestoreAvailable({
    required this.mode,
    required this.discovery,
    this.selectedSource,
    this.needsOldPin = false,
    this.errorMessage,
  });

  final UserMode mode;
  final OnboardingBackupDiscovery discovery;
  final OnboardingRestoreSource? selectedSource;
  final bool needsOldPin;
  final String? errorMessage;

  @override
  List<Object?> get props => [
    mode,
    discovery,
    selectedSource,
    needsOldPin,
    errorMessage,
  ];
}

/// Restoring chat backup (with progress) and vault key; photo restore runs in background.
final class OnboardingRestoringBackup extends OnboardingState {
  const OnboardingRestoringBackup({
    required this.mode,
    required this.source,
    this.chatProgress,
    this.restoreChat = true,
  });

  final UserMode mode;
  final OnboardingRestoreSource source;
  final ChatRestoreProgress? chatProgress;
  final bool restoreChat;

  @override
  List<Object?> get props => [mode, source, chatProgress, restoreChat];
}

/// Vault creation is in progress — show animated progress UI.
final class OnboardingCreatingVault extends OnboardingState {
  const OnboardingCreatingVault({
    required this.mode,
    this.step = VaultCreationStep.generatingKeys,
  });
  final UserMode mode;
  final VaultCreationStep step;
  @override
  List<Object?> get props => [mode, step];
}

/// Discrete step labels shown in the vault creation progress UI.
enum VaultCreationStep {
  generatingKeys,
  wrappingVmk,
  savingToSecureStorage,
  initializingDatabase,
  done,
}

/// Vault created successfully. Navigation to chat happens in this state.
final class OnboardingVaultCreated extends OnboardingState {
  const OnboardingVaultCreated({
    required this.mode,
    required this.vaultId,
    this.vmkBackupPending = false,
    this.restoredMessages = 0,
    this.backgroundPhotoRestoreStarted = false,
  });
  final UserMode mode;
  final String vaultId;

  /// True when Google VMK backup was attempted but failed — show a warning.
  final bool vmkBackupPending;
  final int restoredMessages;
  final bool backgroundPhotoRestoreStarted;
  @override
  List<Object?> get props => [
    mode,
    vaultId,
    vmkBackupPending,
    restoredMessages,
    backgroundPhotoRestoreStarted,
  ];
}

/// Terminal error state. [canRetry] controls whether the UI shows a retry.
final class OnboardingError extends OnboardingState {
  const OnboardingError({required this.message, this.canRetry = true});
  final String message;
  final bool canRetry;
  @override
  List<Object?> get props => [message, canRetry];
}
