import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../application/services/import_manager.dart';
import '../../application/services/chat_vault_bridge.dart';
import '../../application/services/restore_flow_service.dart';
import '../../application/services/pin_validator.dart';
import '../../application/services/vault_session.dart';
import '../../application/usecases/change_pin_usecase.dart';
import '../../application/usecases/create_vault_usecase.dart';
import '../../application/usecases/export_photo_usecase.dart';
import '../../application/usecases/unlock_vault_usecase.dart';
import '../../crypto/services/aes_gcm_crypto_service.dart';
import '../../crypto/services/crypto_service.dart';
import '../../data/repositories_impl/firebase_auth_repository.dart';
import '../../data/repositories_impl/flutter_secure_string_kv.dart';
import '../../data/repositories_impl/google_drive_vmk_repository.dart';
import '../../data/repositories_impl/in_memory_auth_repository.dart';
import '../../data/repositories_impl/in_memory_photo_repository.dart';
import '../../data/repositories_impl/in_memory_secure_storage_repository.dart';
import '../../data/repositories_impl/in_memory_settings_repository.dart';
import '../../data/repositories_impl/in_memory_vault_repository.dart';
import '../../data/repositories_impl/local_vmk_backup_repository.dart';
import '../../data/repositories_impl/persistent_photo_repository.dart';
import '../../data/repositories_impl/persistent_settings_repository.dart';
import '../../data/repositories_impl/persistent_vault_repository.dart';
import '../../data/repositories_impl/secure_storage_flutter_repository.dart';
import '../../data/services/backup_restore_flow_service.dart';
import '../../data/services/pbkdf2_kdf_service.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/photo_repository.dart';
import '../../domain/repositories/secure_storage_repository.dart';
import '../../domain/repositories/settings_repository.dart';
import '../../domain/repositories/vault_repository.dart';
import '../../domain/repositories/vmk_backup_repository.dart';
import 'chat_dependencies.dart';

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
        ? PersistentSettingsRepository(FlutterSecureStringKv(defaultSecureStorage))
        : InMemorySettingsRepository();
    final photoRepository = persistentState
        ? PersistentPhotoRepositoryImpl()
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

    final restoreFlowService = BackupRestoreFlowService(
      secureStorageRepository: secureStorageRepository,
      backupRepositories: backupRepositories,
    );

    final createVaultUseCase = CreateVaultUseCase(
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
      restoreFlowService: restoreFlowService,
      createVaultUseCase: createVaultUseCase,
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
    required this.restoreFlowService,
    required this.createVaultUseCase,
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
  final RestoreFlowService restoreFlowService;
  final CreateVaultUseCase createVaultUseCase;
  final UnlockVaultUseCase unlockVaultUseCase;
  final ChangePinUseCase changePinUseCase;
  final ExportPhotoUseCase exportPhotoUseCase;
  final ImportManager importManager;

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
  late final ChatDependencies chat = ChatDependencies(
    authRepository: authRepository,
    vaultSession: vaultSession,
    database: switch (photoRepository) {
      final PersistentPhotoRepositoryImpl repository => repository.database,
      _ => null,
    },
  );

  bool _chatInitialised = false;

  /// Touches [chat] and records that it now needs disposing.
  ChatDependencies get chatDependencies {
    _chatInitialised = true;
    return chat;
  }

  /// Runs one-time async setup (e.g. opening the local database) that can't
  /// happen in the synchronous factory constructor.
  Future<void> initialize() async {
    if (photoRepository case final PersistentPhotoRepositoryImpl repository) {
      await repository.initialize();
    }
  }

  /// Releases resources held by dependencies that need explicit teardown.
  Future<void> dispose() async {
    vaultSession.lock();
    if (_chatInitialised) chat.dispose();
    if (photoRepository case final PersistentPhotoRepositoryImpl repository) {
      await repository.close();
    }
  }
}
