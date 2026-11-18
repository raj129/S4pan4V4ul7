import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/core/session/vault_session.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_secure_storage_repository.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_vault_repository.dart';
import 'package:photo_vault/features/vault/application/usecases/restore_vault_usecase.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/features/vault/data/services/pbkdf2_kdf_service.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_settings.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_status.dart';
import 'package:photo_vault/features/vault/domain/repositories/vmk_backup_repository.dart';

class _MemoryVmkRepository implements VmkBackupRepository {
  final Map<String, Map<String, String>> backups = {};
  Object? listError;
  Object? restoreError;

  @override
  Future<void> backupVmk({
    required String vaultId,
    required Map<String, String> payload,
    bool interactive = false,
  }) async {
    backups[vaultId] = payload;
  }

  @override
  Future<bool> hasBackup(String vaultId, {bool interactive = false}) async =>
      backups.containsKey(vaultId);

  @override
  Future<List<String>> listVaultIds({bool interactive = false}) async {
    final error = listError;
    if (error != null) throw error;
    return backups.keys.toList();
  }

  @override
  Future<Map<String, String>?> restoreVmk(
    String vaultId, {
    bool interactive = false,
  }) async {
    final error = restoreError;
    if (error != null) throw error;
    return backups[vaultId];
  }
}

void main() {
  const originalPin = '1357';
  const newPin = '2468';
  const vaultId = 'original-vault-id';
  late AesGcmCryptoService crypto;
  late Pbkdf2KdfService kdf;
  late InMemoryVaultRepository vaultRepository;
  late InMemorySecureStorageRepository secureStorage;
  late VaultSession session;
  late _MemoryVmkRepository local;
  late _MemoryVmkRepository cloud;
  late RestoreVaultUseCase useCase;

  Future<Map<String, String>> makePayload(String id, String pin) async {
    final vmk = List<int>.generate(32, (index) => index + 1);
    final salt = kdf.generateSalt();
    final kek = await kdf.deriveKey(pin, salt);
    try {
      final wrapped = await crypto.wrapKey(
        vmk,
        kek,
        keyId: id,
        aad: utf8.encode('$id:vmk:v1'),
      );
      return {
        'wrappedVmk': base64Encode(wrapped.wrappedBytes),
        'nonce': base64Encode(wrapped.nonce),
        'mac': base64Encode(wrapped.mac),
        'salt': base64Encode(salt),
        'encVersion': wrapped.encryptionVersion.toString(),
      };
    } finally {
      try {
        kek.fillRange(0, kek.length, 0);
      } catch (_) {}
      vmk.fillRange(0, vmk.length, 0);
    }
  }

  setUp(() {
    crypto = AesGcmCryptoService();
    kdf = Pbkdf2KdfService(iterations: 1000);
    vaultRepository = InMemoryVaultRepository();
    secureStorage = InMemorySecureStorageRepository();
    session = VaultSession();
    local = _MemoryVmkRepository();
    cloud = _MemoryVmkRepository();
    useCase = RestoreVaultUseCase(
      cryptoService: crypto,
      kdfService: kdf,
      vaultRepository: vaultRepository,
      secureStorageRepository: secureStorage,
      vaultSession: session,
      backupRepositories: [local, cloud],
    );
  });

  test('lists distinct vault IDs from every backup repository', () async {
    local.backups['vault-b'] = const {};
    cloud.backups['vault-a'] = const {};
    cloud.backups['vault-b'] = const {};

    expect(await useCase.listVaultIds(), ['vault-a', 'vault-b']);
  });

  test(
    'restores the same vault ID and rewraps its key with the new PIN',
    () async {
      cloud.backups[vaultId] = await makePayload(vaultId, originalPin);
      await vaultRepository.initializeVault(
        vaultId: 'old-local-vault',
        settings: VaultSettings.defaults(mode: UserMode.localOnly),
      );
      await secureStorage.storeWrappedVmk(
        vaultId: 'old-local-vault',
        wrappedVmkBase64: 'old',
        nonceBase64: 'old',
        macBase64: 'old',
        saltBase64: 'old',
        encVersion: 1,
      );
      session.unlock(
        vaultId: 'old-local-vault',
        vmkBytes: [9, 8, 7],
        pin: '9999',
      );

      await useCase.execute(
        vaultId: vaultId,
        originalPin: originalPin,
        newPin: newPin,
      );

      expect(await vaultRepository.getActiveVaultId(), vaultId);
      expect(session.vaultId, vaultId);
      expect(await secureStorage.loadWrappedVmk('old-local-vault'), isNotNull);

      final restoredSession = VaultSession();
      final unlock = UnlockVaultUseCase(
        vaultRepository: vaultRepository,
        secureStorageRepository: secureStorage,
        kdfService: kdf,
        cryptoService: crypto,
        vaultSession: restoredSession,
      );
      expect(await unlock.execute(newPin), isTrue);
      expect(restoredSession.vaultId, vaultId);
      expect(await unlock.execute(originalPin), isFalse);
    },
  );

  test(
    'wrong original PIN does not change the active vault or stored key',
    () async {
      cloud.backups[vaultId] = await makePayload(vaultId, originalPin);

      await expectLater(
        useCase.execute(vaultId: vaultId, originalPin: '0000', newPin: newPin),
        throwsA(isA<VaultBackupPinException>()),
      );

      expect(await vaultRepository.getActiveVaultId(), isNull);
      expect(await vaultRepository.getStatus(), isNot(VaultStatus.ready));
      expect(secureStorage.debugAllKeys(), isEmpty);
      expect(session.isUnlocked, isFalse);
    },
  );

  test('reports when no selected vault backup exists', () async {
    await expectLater(
      useCase.execute(
        vaultId: vaultId,
        originalPin: originalPin,
        newPin: newPin,
      ),
      throwsA(isA<VaultBackupNotFoundException>()),
    );
  });

  test('rejects malformed VMK backup payloads', () async {
    cloud.backups[vaultId] = const {'wrappedVmk': 'invalid'};

    await expectLater(
      useCase.execute(
        vaultId: vaultId,
        originalPin: originalPin,
        newPin: newPin,
      ),
      throwsA(isA<VaultBackupFormatException>()),
    );
  });
}
