import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/usecases/create_vault_usecase.dart';
import 'package:photo_vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/data/repositories_impl/in_memory_secure_storage_repository.dart';
import 'package:photo_vault/data/repositories_impl/in_memory_vault_repository.dart';
import 'package:photo_vault/data/services/pbkdf2_kdf_service.dart';
import 'package:photo_vault/domain/entities/user_mode.dart';

void main() {
  group('UnlockVaultUseCase', () {
    late InMemoryVaultRepository vaultRepo;
    late InMemorySecureStorageRepository secureRepo;
    late Pbkdf2KdfService kdfService;
    late AesGcmCryptoService cryptoService;
    late CreateVaultUseCase createUseCase;
    late UnlockVaultUseCase unlockUseCase;

    setUp(() {
      vaultRepo = InMemoryVaultRepository();
      secureRepo = InMemorySecureStorageRepository();
      kdfService = Pbkdf2KdfService(iterations: 1000);
      cryptoService = AesGcmCryptoService();
      createUseCase = CreateVaultUseCase(
        cryptoService: cryptoService,
        kdfService: kdfService,
        vaultRepository: vaultRepo,
        secureStorageRepository: secureRepo,
      );
      unlockUseCase = UnlockVaultUseCase(
        vaultRepository: vaultRepo,
        secureStorageRepository: secureRepo,
        kdfService: kdfService,
        cryptoService: cryptoService,
      );
    });

    test('returns true with correct PIN', () async {
      await createUseCase.execute(
        pin: '847291',
        mode: UserMode.localOnly,
        biometricEnabled: false,
      );

      final ok = await unlockUseCase.execute('847291');
      expect(ok, isTrue);
    });

    test('returns false with incorrect PIN', () async {
      await createUseCase.execute(
        pin: '847291',
        mode: UserMode.localOnly,
        biometricEnabled: false,
      );

      final ok = await unlockUseCase.execute('847292');
      expect(ok, isFalse);
    });

    test('returns false when no vault exists', () async {
      final ok = await unlockUseCase.execute('847291');
      expect(ok, isFalse);
    });
  });
}
