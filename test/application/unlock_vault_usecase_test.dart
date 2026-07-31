import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/vault_session.dart';
import 'package:photo_vault/application/usecases/create_vault_usecase.dart';
import 'package:photo_vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/data/repositories_impl/in_memory_secure_storage_repository.dart';
import 'package:photo_vault/data/repositories_impl/in_memory_vault_repository.dart';
import 'package:photo_vault/data/services/pbkdf2_kdf_service.dart';
import 'package:photo_vault/domain/entities/user_mode.dart';
import 'package:photo_vault/domain/repositories/vmk_backup_repository.dart';

void main() {
  group('UnlockVaultUseCase', () {
    late InMemoryVaultRepository vaultRepo;
    late InMemorySecureStorageRepository secureRepo;
    late Pbkdf2KdfService kdfService;
    late AesGcmCryptoService cryptoService;
    late CreateVaultUseCase createUseCase;
    late UnlockVaultUseCase unlockUseCase;

    setUp(() {
      final vaultSession = VaultSession();
      vaultRepo = InMemoryVaultRepository();
      secureRepo = InMemorySecureStorageRepository();
      kdfService = Pbkdf2KdfService(iterations: 1000);
      cryptoService = AesGcmCryptoService();
      createUseCase = CreateVaultUseCase(
        cryptoService: cryptoService,
        kdfService: kdfService,
        vaultRepository: vaultRepo,
        secureStorageRepository: secureRepo,
        vaultSession: vaultSession,
        backupRepositories: [_NoopVmkBackupRepository()],
      );
      unlockUseCase = UnlockVaultUseCase(
        vaultRepository: vaultRepo,
        secureStorageRepository: secureRepo,
        kdfService: kdfService,
        cryptoService: cryptoService,
        vaultSession: vaultSession,
      );
    });

    test('returns true with correct PIN', () async {
      await createUseCase.execute(
        pin: '8472',
        mode: UserMode.localOnly,
      );

      final ok = await unlockUseCase.execute('8472');
      expect(ok, isTrue);
    });

    test('returns false with incorrect PIN', () async {
      await createUseCase.execute(
        pin: '8472',
        mode: UserMode.localOnly,
      );

      final ok = await unlockUseCase.execute('8473');
      expect(ok, isFalse);
    });

    test('returns false when no vault exists', () async {
      final ok = await unlockUseCase.execute('8472');
      expect(ok, isFalse);
    });
  });
}

class _NoopVmkBackupRepository implements VmkBackupRepository {
  @override
  Future<void> backupVmk({
    required String vaultId,
    required Map<String, String> payload,
  }) async {}

  @override
  Future<bool> hasBackup(String vaultId) async => false;

  @override
  Future<List<String>> listVaultIds() async => const [];

  @override
  Future<Map<String, String>?> restoreVmk(String vaultId) async => null;
}
