import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/session/vault_session.dart';
import 'package:photo_vault/features/vault/application/usecases/create_vault_usecase.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/core/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_secure_storage_repository.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_vault_repository.dart';
import 'package:photo_vault/features/vault/data/services/pbkdf2_kdf_service.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/repositories/unlock_attempt_store.dart';
import 'package:photo_vault/features/vault/domain/repositories/vmk_backup_repository.dart';

void main() {
  group('UnlockVaultUseCase', () {
    late InMemoryVaultRepository vaultRepo;
    late InMemorySecureStorageRepository secureRepo;
    late Pbkdf2KdfService kdfService;
    late AesGcmCryptoService cryptoService;
    late CreateVaultUseCase createUseCase;
    late UnlockVaultUseCase unlockUseCase;
    late InMemoryUnlockAttemptStore attempts;
    var now = DateTime(2026, 1, 1);

    setUp(() {
      now = DateTime(2026, 1, 1);
      attempts = InMemoryUnlockAttemptStore();
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
        attemptStore: attempts,
        clock: () => now,
      );
    });

    test('returns true with correct PIN', () async {
      await createUseCase.execute(pin: '8472', mode: UserMode.localOnly);

      final ok = await unlockUseCase.execute('8472');
      expect(ok, isTrue);
    });

    test('returns false with incorrect PIN', () async {
      await createUseCase.execute(pin: '8472', mode: UserMode.localOnly);

      final ok = await unlockUseCase.execute('8473');
      expect(ok, isFalse);
    });

    test('returns false when no vault exists', () async {
      final ok = await unlockUseCase.execute('8472');
      expect(ok, isFalse);
    });

    test('locks out after repeated failures, even for the right PIN', () async {
      await createUseCase.execute(pin: '8472', mode: UserMode.localOnly);

      for (var i = 0; i < 3; i++) {
        expect(await unlockUseCase.execute('0000'), isFalse);
      }
      expect(await unlockUseCase.lockoutRemaining(), isNotNull);
      expect(await unlockUseCase.execute('8472'), isFalse);

      now = now.add(const Duration(seconds: 11));
      expect(await unlockUseCase.lockoutRemaining(), isNull);
      expect(await unlockUseCase.execute('8472'), isTrue);
      expect(await unlockUseCase.lockoutRemaining(), isNull);
    });

    test('lockout persists across use case instances', () async {
      await createUseCase.execute(pin: '8472', mode: UserMode.localOnly);
      for (var i = 0; i < 3; i++) {
        await unlockUseCase.execute('0000');
      }
      final restarted = UnlockVaultUseCase(
        vaultRepository: vaultRepo,
        secureStorageRepository: secureRepo,
        kdfService: kdfService,
        cryptoService: cryptoService,
        vaultSession: VaultSession(),
        attemptStore: attempts,
        clock: () => now,
      );
      expect(await restarted.lockoutRemaining(), isNotNull);
    });

    test('a missing vault does not count as a failed attempt', () async {
      for (var i = 0; i < 5; i++) {
        await unlockUseCase.execute('0000');
      }
      expect(await unlockUseCase.lockoutRemaining(), isNull);
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
