import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/vault/application/services/import_manager.dart';
import '../integrations/chat_vault_bridge.dart';
import '../../features/vault/application/services/restore_flow_service.dart';
import '../../features/vault/application/services/pin_validator.dart';
import '../session/vault_session.dart';
import '../../features/vault/application/usecases/change_pin_usecase.dart';
import '../../features/vault/application/usecases/create_vault_usecase.dart';
import '../../features/vault/application/usecases/export_photo_usecase.dart';
import '../../features/vault/application/usecases/restore_vault_usecase.dart';
import '../../features/vault/application/usecases/unlock_vault_usecase.dart';
import '../crypto/services/aes_gcm_crypto_service.dart';
import '../crypto/services/crypto_service.dart';
import '../data/repositories/firebase_auth_repository.dart';
import '../../features/vault/data/repositories/flutter_secure_string_kv.dart';
import '../../features/vault/data/repositories/google_drive_vmk_repository.dart';
import '../data/repositories/in_memory_auth_repository.dart';
import '../testing/repositories/in_memory_photo_repository.dart';
import '../testing/repositories/in_memory_secure_storage_repository.dart';
import '../testing/repositories/in_memory_settings_repository.dart';
import '../testing/repositories/in_memory_vault_repository.dart';
import '../../features/vault/data/repositories/local_vmk_backup_repository.dart';
import '../../features/vault/data/repositories/persistent_photo_repository.dart';
import '../../features/vault/data/repositories/persistent_settings_repository.dart';
import '../../features/vault/data/repositories/persistent_vault_repository.dart';
import '../../features/vault/data/repositories/secure_storage_flutter_repository.dart';
import '../../features/vault/data/repositories/unlock_attempt_stores.dart';
import '../../features/vault/data/services/backup_restore_flow_service.dart';
import '../../features/vault/data/services/pbkdf2_kdf_service.dart';
import '../domain/repositories/auth_repository.dart';
import '../../features/vault/domain/repositories/photo_repository.dart';
import '../../features/vault/domain/repositories/secure_storage_repository.dart';
import '../../features/vault/domain/repositories/settings_repository.dart';
import '../../features/vault/domain/repositories/vault_repository.dart';
import '../../features/vault/domain/repositories/vmk_backup_repository.dart';
import '../../features/chat/application/services/chat_identity_service.dart';
import '../../features/chat/di/chat_dependencies.dart';
import '../../features/backup/application/backup_coordinator.dart';
import '../../features/backup/application/backup_manager.dart';
import '../../features/backup/application/backup_network.dart';
import '../../features/backup/application/backup_scheduler.dart';
import '../../features/backup/application/photo_hash_cache.dart';
import '../../features/backup/application/vault_backup_key_service.dart';
import '../../features/backup/application/vault_photo_backup_service.dart';
import '../../features/backup/data/drive_backup_blob_store.dart';
import '../../features/backup/data/local_backup_blob_store.dart';

import '../location/app_location.dart';
import '../location/mock/traffic_route_service.dart';

/// Single composition root for the vault side of the app.
///
/// Wires every repository, service, and use case exactly once and exposes
/// them as plain fields. This replaces the ad-hoc `late final` wiring that
/// used to live directly inside `_VaultAppState`, so dependency
/// construction can be understood, tested, and swapped in one place instead
/// of being interleaved with widget/router code.
///
/// Callers own the instance's lifecycle: call [initialize] once after
/// construction and [dispose] when the app root is torn down.
class AppDependencies {
  factory AppDependencies({required bool persistentState}) {
    const defaultSecureStorage = FlutterSecureStorage();

    final vaultRepository = persistentState
        ? PersistentVaultRepository(FlutterSecureStringKv(defaultSecureStorage))
        : InMemoryVaultRepository();
    final secureStorageRepository = persistentState
        ? SecureStorageFlutterRepository(defaultSecureStorage)
        : InMemorySecureStorageRepository();
    final settingsRepository = persistentState
        ? PersistentSettingsRepository(
            FlutterSecureStringKv(defaultSecureStorage),
          )
        : InMemorySettingsRepository();
    final PhotoRepository photoRepository = persistentState
        ? PersistentPhotoRepositoryImpl(
            currentVaultId: vaultRepository.getActiveVaultId,
          )
        : InMemoryPhotoRepository();
    final authRepository = persistentState
        ? FirebaseAuthRepository()
        : InMemoryAuthRepository();

    final cryptoService = AesGcmCryptoService();
    final kdfService = Pbkdf2KdfService();
    final vaultSession = VaultSession();
    final pinValidator = PinValidator();

    final backupRepositories = <VmkBackupRepository>[
      LocalVmkBackupRepository(),
      GoogleDriveVmkRepository(authRepository: authRepository),
    ];

    final createVaultUseCase = CreateVaultUseCase(
      cryptoService: cryptoService,
      kdfService: kdfService,
      vaultRepository: vaultRepository,
      secureStorageRepository: secureStorageRepository,
      vaultSession: vaultSession,
      backupRepositories: backupRepositories,
    );
    final restoreVaultUseCase = RestoreVaultUseCase(
      cryptoService: cryptoService,
      kdfService: kdfService,
      vaultRepository: vaultRepository,
      secureStorageRepository: secureStorageRepository,
      vaultSession: vaultSession,
      backupRepositories: backupRepositories,
    );
    final unlockVaultUseCase = UnlockVaultUseCase(
      vaultRepository: vaultRepository,
      secureStorageRepository: secureStorageRepository,
      kdfService: kdfService,
      cryptoService: cryptoService,
      vaultSession: vaultSession,
      attemptStore: persistentState
          ? PersistentUnlockAttemptStore(
              FlutterSecureStringKv(defaultSecureStorage),
            )
          : null,
    );
    final changePinUseCase = ChangePinUseCase(
      vaultRepository: vaultRepository,
      secureStorageRepository: secureStorageRepository,
      kdfService: kdfService,
      cryptoService: cryptoService,
      vaultSession: vaultSession,
    );
    final exportPhotoUseCase = ExportPhotoUseCase(
      cryptoService: cryptoService,
      vaultSession: vaultSession,
    );
    final importManager = ImportManager(
      photoRepository: photoRepository,
      cryptoService: cryptoService,
      vaultSession: vaultSession,
    );

    return AppDependencies._(
      vaultRepository: vaultRepository,
      secureStorageRepository: secureStorageRepository,
      settingsRepository: settingsRepository,
      photoRepository: photoRepository,
      authRepository: authRepository,
      cryptoService: cryptoService,
      vaultSession: vaultSession,
      pinValidator: pinValidator,
      backupRepositories: backupRepositories,
      createVaultUseCase: createVaultUseCase,
      restoreVaultUseCase: restoreVaultUseCase,
      unlockVaultUseCase: unlockVaultUseCase,
      changePinUseCase: changePinUseCase,
      exportPhotoUseCase: exportPhotoUseCase,
      importManager: importManager,
    );
  }

  AppDependencies._({
    required this.vaultRepository,
    required this.secureStorageRepository,
    required this.settingsRepository,
    required this.photoRepository,
    required this.authRepository,
    required this.cryptoService,
    required this.vaultSession,
    required this.pinValidator,
    required this.backupRepositories,
    required this.createVaultUseCase,
    required this.restoreVaultUseCase,
    required this.unlockVaultUseCase,
    required this.changePinUseCase,
    required this.exportPhotoUseCase,
    required this.importManager,
  });

  final VaultRepository vaultRepository;
  final SecureStorageRepository secureStorageRepository;
  final SettingsRepository settingsRepository;
  final PhotoRepository photoRepository;
  final AuthRepository authRepository;
  final CryptoService cryptoService;
  final VaultSession vaultSession;
  final PinValidator pinValidator;
  final List<VmkBackupRepository> backupRepositories;
  final CreateVaultUseCase createVaultUseCase;
  final RestoreVaultUseCase restoreVaultUseCase;
  final UnlockVaultUseCase unlockVaultUseCase;
  final ChangePinUseCase changePinUseCase;
  final ExportPhotoUseCase exportPhotoUseCase;
  final ImportManager importManager;

  /// Process-wide location provider (real GPS or mock).
  AppLocation get location => AppLocation.instance;

  bool get _canTouchChat =>
      chatOverride != null || _chatInitialised || Firebase.apps.isNotEmpty;

  /// Vault-bound manifest encryption keys (one-way HKDF-SHA256 from VMK).
  late final VaultBackupKeyService vaultBackupKeys = VaultBackupKeyService(
    secureStorageRepository,
  );

  /// Vault photo backup to this device and Google Drive.
  late final VaultPhotoBackupService vaultPhotoBackup = VaultPhotoBackupService(
    stores: [
      LocalBackupBlobStore(),
      DriveBackupBlobStore(authRepository: authRepository),
    ],
    photoRepository: photoRepository,
    listPhotos: () => switch (photoRepository) {
      final VaultAttachmentRepository repository =>
        repository.listAttachments(),
      _ => throw StateError('Vault photos are unavailable in this mode.'),
    },
    vaultBackupKeys: vaultBackupKeys,
    legacyCrypto: () => _canTouchChat ? chatDependencies.cryptoService : null,
    settings: settingsRepository,
    currentUid: () =>
        _canTouchChat ? chatDependencies.authService.currentUid : null,
    networkAllowed: () => backupNetworkAllowed(settingsRepository),
    currentVaultId: () async =>
        vaultSession.vaultId ?? await vaultRepository.getActiveVaultId(),
    hashCache: PhotoHashCache.defaults(),
    coordinator: BackupCoordinator.shared,
  );

  /// App-scoped backup & restore state + background catch-up coordinator.
  late final BackupManager backupManager = BackupManager(
    settingsRepository: settingsRepository,
    chatBackup: () =>
        _canTouchChat ? chatDependencies.backupService : null,
    vaultPhotoBackup: () => vaultPhotoBackup,
    authRepository: authRepository,
    scheduleCatchUp: schedulePendingBackupCatchUp,
  );

  /// Google vault recovery uses the same ID/key and optionally restores photos.
  late final RestoreFlowService restoreFlowService = BackupRestoreFlowService(
    restoreVaultUseCase: restoreVaultUseCase,
    vaultRepository: vaultRepository,
    onVaultRestored: ({
      required vaultId,
      required originalPin,
      required newPin,
    }) async {
      await settingsRepository.setBackupCloudEnabled(true);
      await settingsRepository.setDriveEncryptedBackupEnabled(true);
      if (!_canTouchChat) return;
      try {
        final uid = chatDependencies.authService.currentUid;
        if (uid == null) return;
        final synced = await chatDependencies.identityService.sync(
          uid: uid,
          pin: originalPin,
        );
        if (newPin != originalPin &&
            (synced == IdentitySyncResult.restored ||
                synced == IdentitySyncResult.upToDate)) {
          await chatDependencies.identityService.rewrapForNewPin(
            uid: uid,
            newPin: newPin,
          );
        }
      } catch (_) {
        // Vault VMK recovery still succeeds even if chat key sync is offline.
      }
    },
    restorePhotos: () async {
      final result = await vaultPhotoBackup.restore(
        interactive: true,
        includeCloud: true,
      );
      return RestorePhotosSummary(
        foundBackup: result.foundBackup,
        restored: result.restored,
        alreadyPresent: result.alreadyPresent,
        unavailable: result.unavailable,
        failures: result.failures,
      );
    },
  );

  /// Traffic-aware routes for the mock route simulator.
  late final TrafficRouteService trafficRouteService = TrafficRouteService();

  /// Bridge for moving media between the vault and chat.
  ///
  /// Lives on [AppDependencies] rather than [ChatDependencies] because it needs
  /// the vault's repositories, which chat must not depend on directly.
  late final ChatVaultBridge chatVaultBridge = ChatVaultBridge(
    photoRepository: photoRepository,
    exportPhoto: exportPhotoUseCase,
    importManager: importManager,
  );

  /// Chat feature dependencies.
  ///
  /// Lazy because every member reaches for Firebase, which is unavailable in
  /// the in-memory test configuration.
  late final ChatDependencies chat = () {
    final deps = ChatDependencies(
      authRepository: authRepository,
      vaultSession: vaultSession,
      settingsRepository: settingsRepository,
      databaseProvider: () => switch (photoRepository) {
        final PersistentPhotoRepositoryImpl repository => repository.database,
        _ => null,
      },
    );
    // Apply the stored "Show last seen" privacy setting as soon as chat exists,
    // going through the service so an already-published presence is updated.
    unawaited(
      settingsRepository
          .isShowLastSeenEnabled()
          .then(deps.presenceService.setShareLastSeen)
          .catchError((Object _) {}),
    );
    return deps;
  }();

  bool _chatInitialised = false;
  Future<void>? _initialization;
  ChatDependencies? chatOverride;

  /// Touches [chat] and records that it now needs disposing.
  ChatDependencies get chatDependencies {
    if (chatOverride != null) return chatOverride!;
    _chatInitialised = true;
    return chat;
  }

  /// Runs one-time async setup (e.g. opening the local database) that can't
  /// happen in the synchronous factory constructor.
  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    if (photoRepository case final PersistentPhotoRepositoryImpl repository) {
      await repository.initialize();
    }
  }

  /// Releases resources held by dependencies that need explicit teardown.
  Future<void> dispose() async {
    vaultSession.lock();
    backupManager.dispose();
    if (_chatInitialised) chat.dispose();
    await _initialization;
    if (photoRepository case final PersistentPhotoRepositoryImpl repository) {
      await repository.close();
    }
  }
}
