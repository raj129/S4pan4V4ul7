import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/application/usecases/create_vault_usecase.dart';
import 'package:photo_vault/application/services/vault_session.dart';
import 'package:photo_vault/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/data/repositories_impl/in_memory_secure_storage_repository.dart';
import 'package:photo_vault/data/repositories_impl/in_memory_vault_repository.dart';
import 'package:photo_vault/data/services/pbkdf2_kdf_service.dart';
import 'package:photo_vault/domain/entities/user_mode.dart';
import 'package:photo_vault/domain/entities/vault_status.dart';

void main() {
  group('CreateVaultUseCase', () {
    late CreateVaultUseCase useCase;
    late InMemoryVaultRepository vaultRepo;
    late InMemorySecureStorageRepository secureRepo;

    setUp(() {
      vaultRepo = InMemoryVaultRepository();
      secureRepo = InMemorySecureStorageRepository();
      useCase = CreateVaultUseCase(
        cryptoService: AesGcmCryptoService(),
        kdfService: Pbkdf2KdfService(iterations: 1000), // fast for tests
        vaultRepository: vaultRepo,
        secureStorageRepository: secureRepo,
        vaultSession: VaultSession(),
      );
    });

    test('creates vault in local-only mode successfully', () async {
      final vaultId = await useCase.execute(
        pin: '847291',
        mode: UserMode.localOnly,
      );

      expect(vaultId, isNotEmpty);
      expect(await vaultRepo.getStatus(), VaultStatus.ready);
    });

    test('persists wrapped VMK in secure storage', () async {
      final vaultId = await useCase.execute(
        pin: '847291',
        mode: UserMode.localOnly,
      );

      final stored = await secureRepo.loadWrappedVmk(vaultId);
      expect(stored, isNotNull);
      expect(stored!['wrappedVmk'], isNotEmpty);
      expect(stored['salt'], isNotEmpty);
    });

    test('cleans up on failure — vault status remains notCreated', () async {
      final failingUseCase = CreateVaultUseCase(
        cryptoService: AesGcmCryptoService(),
        kdfService: _AlwaysFailKdfService(),
        vaultRepository: vaultRepo,
        secureStorageRepository: secureRepo,
        vaultSession: VaultSession(),
      );

      await expectLater(
        failingUseCase.execute(
          pin: '847291',
          mode: UserMode.localOnly,
        ),
        throwsA(isA<VaultCreationException>()),
      );

      expect(await vaultRepo.getStatus(), VaultStatus.notCreated);
    });

    test(
      'VMK is not present in secure storage after failed creation',
      () async {
        final failingUseCase = CreateVaultUseCase(
          cryptoService: AesGcmCryptoService(),
          kdfService: _AlwaysFailKdfService(),
          vaultRepository: vaultRepo,
          secureStorageRepository: secureRepo,
          vaultSession: VaultSession(),
        );

        try {
          await failingUseCase.execute(
            pin: '847291',
            mode: UserMode.localOnly,
          );
        } catch (_) {}

        // Secure storage must be empty after cleanup.
        final allRecords = secureRepo.debugAllKeys();
        expect(allRecords, isEmpty);
      },
    );
  });
}

class _AlwaysFailKdfService extends Pbkdf2KdfService {
  _AlwaysFailKdfService() : super(iterations: 1);

  @override
  Future<List<int>> deriveKey(String pin, List<int> saltBytes) {
    throw Exception('Simulated KDF failure');
  }
}
