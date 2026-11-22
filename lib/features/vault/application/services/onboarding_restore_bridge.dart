import 'dart:async';

import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/features/backup/application/backup_manager.dart';
import 'package:photo_vault/features/backup/application/settings_backup_service.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import 'package:photo_vault/features/chat/application/services/chat_identity_service.dart';
import 'package:photo_vault/features/chat/di/chat_dependencies.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/repositories/settings_repository.dart';
import 'package:photo_vault/features/vault/domain/repositories/vault_repository.dart';

import '../usecases/create_vault_usecase.dart';
import '../usecases/restore_vault_usecase.dart';

enum OnboardingRestoreSource { local, googleDrive }

class OnboardingBackupDiscovery {
  const OnboardingBackupDiscovery({
    this.localVaultId,
    this.cloudVaultId,
    this.localVaultIds = const [],
    this.cloudVaultIds = const [],
    this.localChatCandidate,
    this.cloudChatCandidate,
    this.hasLocalSettings = false,
    this.hasCloudSettings = false,
  });

  final String? localVaultId;
  final String? cloudVaultId;
  final List<String> localVaultIds;
  final List<String> cloudVaultIds;
  final ChatBackupCandidate? localChatCandidate;
  final ChatBackupCandidate? cloudChatCandidate;
  final bool hasLocalSettings;
  final bool hasCloudSettings;

  bool get hasLocalVault => localVaultId != null || localVaultIds.isNotEmpty;
  bool get hasCloudVault => cloudVaultId != null || cloudVaultIds.isNotEmpty;
  bool get hasLocalChat => localChatCandidate != null;
  bool get hasCloudChat => cloudChatCandidate != null;
  bool get hasAnySettings => hasLocalSettings || hasCloudSettings;

  List<String> vaultIdsFor(OnboardingRestoreSource source) {
    if (source == OnboardingRestoreSource.googleDrive) {
      if (cloudVaultIds.isNotEmpty) return cloudVaultIds;
      if (cloudVaultId != null) return [cloudVaultId!];
      if (localVaultIds.isNotEmpty) return localVaultIds;
      return localVaultId != null ? [localVaultId!] : const [];
    }
    if (localVaultIds.isNotEmpty) return localVaultIds;
    if (localVaultId != null) return [localVaultId!];
    if (cloudVaultIds.isNotEmpty) return cloudVaultIds;
    return cloudVaultId != null ? [cloudVaultId!] : const [];
  }

  bool get hasLocalBackup => hasLocalVault || hasLocalChat || hasLocalSettings;
  bool get hasCloudBackup => hasCloudVault || hasCloudChat || hasCloudSettings;
  bool get hasAnyBackup => hasLocalBackup || hasCloudBackup;
}

sealed class OnboardingRestoreOutcome {
  const OnboardingRestoreOutcome();
}

final class OnboardingRestoreSuccess extends OnboardingRestoreOutcome {
  const OnboardingRestoreSuccess({
    required this.vaultId,
    this.restoredMessages = 0,
    this.backgroundPhotoRestoreStarted = false,
  });

  final String vaultId;
  final int restoredMessages;
  final bool backgroundPhotoRestoreStarted;
}

final class OnboardingRestoreNeedsOldPin extends OnboardingRestoreOutcome {
  const OnboardingRestoreNeedsOldPin({required this.message});
  final String message;
}

final class OnboardingRestoreFailure extends OnboardingRestoreOutcome {
  const OnboardingRestoreFailure({required this.message});
  final String message;
}

/// Bridges onboarding PIN creation to Vault & Chat backup discovery/restoration.
abstract class OnboardingRestoreBridge {
  Future<OnboardingBackupDiscovery> discoverBackups({required UserMode mode});

  Future<OnboardingRestoreOutcome> restoreFromSource({
    required OnboardingRestoreSource source,
    required OnboardingBackupDiscovery discovery,
    required String newPin,
    required UserMode mode,
    String? oldPin,
    String? selectedVaultId,
    bool restoreVault = true,
    bool restoreChat = true,
    bool restoreVaultPhotos = true,
    bool restoreSettings = true,
    void Function(ChatRestoreProgress)? onChatProgress,
  });

  Future<void> dismissChatRestoreOffer();
}

class DefaultOnboardingRestoreBridge implements OnboardingRestoreBridge {
  DefaultOnboardingRestoreBridge({
    required RestoreVaultUseCase restoreVaultUseCase,
    required CreateVaultUseCase createVaultUseCase,
    required VaultRepository vaultRepository,
    required SettingsRepository settingsRepository,
    required BackupManager backupManager,
    SettingsBackupService? settingsBackupService,
    required ChatDependencies? Function() chatDependencies,
    AuthRepository? authRepository,
  }) : _restoreVaultUseCase = restoreVaultUseCase,
       _createVaultUseCase = createVaultUseCase,
       _vaultRepository = vaultRepository,
       _settingsRepository = settingsRepository,
       _backupManager = backupManager,
       _settingsBackupService = settingsBackupService,
       _chatDependencies = chatDependencies,
       _authRepository = authRepository;

  final RestoreVaultUseCase _restoreVaultUseCase;
  final CreateVaultUseCase _createVaultUseCase;
  final VaultRepository _vaultRepository;
  final SettingsRepository _settingsRepository;
  final BackupManager _backupManager;
  final SettingsBackupService? _settingsBackupService;
  final ChatDependencies? Function() _chatDependencies;
  final AuthRepository? _authRepository;

  @override
  Future<OnboardingBackupDiscovery> discoverBackups({
    required UserMode mode,
  }) async {
    final includeCloud = mode == UserMode.googleEnabled;
    if (includeCloud && _authRepository != null) {
      try {
        await _authRepository
            .warmUpDriveAuthorization(interactive: false)
            .timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    final vaultIds = await _restoreVaultUseCase.listVaultIdsBySource(
      interactive: false,
      includeCloud: includeCloud,
    );

    ChatBackupCandidate? localChat;
    ChatBackupCandidate? cloudChat;
    if (includeCloud) {
      final chat = _chatDependencies();
      if (chat != null) {
        try {
          final candidates = await chat.backupService.inspectAvailableBackups(
            interactive: false,
            includeCloud: true,
            ignoreCloudSetting: true,
          );
          for (final c in candidates) {
            if (c.isCloud) {
              cloudChat ??= c;
            } else {
              localChat ??= c;
            }
          }
        } catch (_) {}
      }
    }

    var hasLocalSettings = false;
    var hasCloudSettings = false;
    final settingsBackup = _settingsBackupService;
    if (settingsBackup != null) {
      try {
        final probed = await settingsBackup.hasBackups(
          interactive: false,
          includeCloud: includeCloud,
        );
        hasLocalSettings = probed.hasLocal;
        hasCloudSettings = probed.hasCloud;
      } catch (_) {}
    }

    return OnboardingBackupDiscovery(
      localVaultId: vaultIds.local.isNotEmpty ? vaultIds.local.first : null,
      cloudVaultId: vaultIds.cloud.isNotEmpty ? vaultIds.cloud.first : null,
      localVaultIds: vaultIds.local,
      cloudVaultIds: vaultIds.cloud,
      localChatCandidate: localChat,
      cloudChatCandidate: cloudChat,
      hasLocalSettings: hasLocalSettings,
      hasCloudSettings: hasCloudSettings,
    );
  }

  @override
  Future<OnboardingRestoreOutcome> restoreFromSource({
    required OnboardingRestoreSource source,
    required OnboardingBackupDiscovery discovery,
    required String newPin,
    required UserMode mode,
    String? oldPin,
    String? selectedVaultId,
    bool restoreVault = true,
    bool restoreChat = true,
    bool restoreVaultPhotos = true,
    bool restoreSettings = true,
    void Function(ChatRestoreProgress)? onChatProgress,
  }) async {
    final pinToUnwrap = oldPin ?? newPin;
    final isCloud = source == OnboardingRestoreSource.googleDrive;
    final availableIds = discovery.vaultIdsFor(source);
    final targetVaultId =
        selectedVaultId ?? (availableIds.isNotEmpty ? availableIds.first : null);
    final useCloudForVault = isCloud
        ? discovery.cloudVaultIds.contains(targetVaultId) ||
              discovery.cloudVaultId == targetVaultId
        : !(discovery.localVaultIds.contains(targetVaultId) ||
                  discovery.localVaultId == targetVaultId) &&
              (discovery.cloudVaultIds.contains(targetVaultId) ||
                  discovery.cloudVaultId == targetVaultId);

    // Step 1: Restore Vault VMK when user chose to restore Vault
    String? vaultId = await _vaultRepository.getActiveVaultId();
    if (restoreVault && vaultId == null && targetVaultId != null) {
      try {
        await _restoreVaultUseCase.execute(
          vaultId: targetVaultId,
          originalPin: pinToUnwrap,
          newPin: newPin,
          cloudOnly: useCloudForVault,
        );
        vaultId = targetVaultId;
      } on VaultBackupPinException {
        return const OnboardingRestoreNeedsOldPin(
          message:
              'Your new PIN did not match the vault backup PIN. Enter your previous 4-digit PIN.',
        );
      } catch (e) {
        return OnboardingRestoreFailure(message: e.toString());
      }
    }

    if (mode == UserMode.googleEnabled) {
      await _settingsRepository.setBackupCloudEnabled(true);
      await _settingsRepository.setDriveEncryptedBackupEnabled(true);
    }

    // Step 2: Reconcile Chat Identity Key & restore Chat Backup (Google mode)
    var restoredMessages = 0;
    if (mode == UserMode.googleEnabled) {
      final chat = _chatDependencies();
      final uid = chat?.authService.currentUid;
      if (chat != null && uid != null && uid.isNotEmpty) {
        try {
          if (restoreChat) {
            final syncResult = await chat.identityService.sync(
              uid: uid,
              pin: pinToUnwrap,
            );
            if (syncResult == IdentitySyncResult.wrongPin) {
              return const OnboardingRestoreNeedsOldPin(
                message:
                    'Your new PIN did not match your chat history PIN. Enter your previous 4-digit PIN.',
              );
            }
            if (oldPin != null &&
                oldPin != newPin &&
                (syncResult == IdentitySyncResult.restored ||
                    syncResult == IdentitySyncResult.upToDate)) {
              await chat.identityService.rewrapForNewPin(
                uid: uid,
                newPin: newPin,
              );
            }

            final chatCandidate = isCloud
                ? (discovery.cloudChatCandidate ?? discovery.localChatCandidate)
                : (discovery.localChatCandidate ?? discovery.cloudChatCandidate);
            if (chatCandidate != null) {
              restoredMessages = await chat.backupService.restoreCandidate(
                chatCandidate,
                onProgress: onChatProgress,
              );
            } else {
              // Fallback: re-probe interactively in case Drive wasn't cached
              // during non-interactive discovery.
              final snapshot = await chat.backupService.findLatestBackup(
                interactive: true,
                cloudOnly: isCloud ? true : null,
                ignoreCloudSetting: true,
                onProgress: onChatProgress,
              );
              if (snapshot != null) {
                restoredMessages = await chat.backupService.restore(
                  snapshot,
                  onProgress: onChatProgress,
                );
              } else {
                await chat.backupService.dismissRestoreOffer();
              }
            }
          } else {
            await chat.backupService.dismissRestoreOffer();
          }
        } catch (e) {
          return OnboardingRestoreFailure(
            message: 'Could not restore chat backup: $e',
          );
        }
      }
    }

    // Step 3: If no vault backup was restored, create a fresh vault.
    vaultId ??= await _createVaultUseCase.execute(pin: newPin, mode: mode);

    // Step 3b: Restore portable app settings if available and requested.
    if (restoreSettings &&
        _settingsBackupService != null &&
        discovery.hasAnySettings) {
      try {
        final res = await _settingsBackupService.restore(
          interactive: isCloud,
          includeCloud: mode == UserMode.googleEnabled,
          preferCloud: isCloud,
        );
        if (res.foundBackup && res.appliedCount > 0) {
          await _backupManager.onSettingsChanged?.call();
        }
      } catch (_) {}
    }

    // Step 4: Start vault photo restore in the background (non-blocking).
    final startPhotos =
        restoreVault && restoreVaultPhotos && targetVaultId != null;
    if (startPhotos) {
      _backupManager.startVaultPhotoRestoreInBackground(
        includeCloud: mode == UserMode.googleEnabled,
      );
    }

    return OnboardingRestoreSuccess(
      vaultId: vaultId,
      restoredMessages: restoredMessages,
      backgroundPhotoRestoreStarted: startPhotos,
    );
  }

  @override
  Future<void> dismissChatRestoreOffer() async {
    try {
      await _chatDependencies()?.backupService.dismissRestoreOffer();
    } catch (_) {}
  }
}
