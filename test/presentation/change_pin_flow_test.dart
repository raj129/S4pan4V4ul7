import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/core/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/core/session/vault_session.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_secure_storage_repository.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_vault_repository.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/change_pin_usecase.dart';
import 'package:photo_vault/features/vault/application/usecases/create_vault_usecase.dart';
import 'package:photo_vault/features/vault/data/services/pbkdf2_kdf_service.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/repositories/vmk_backup_repository.dart';
import 'package:photo_vault/features/vault/presentation/screens/settings/change_pin_screen.dart';

const _currentPin = '8472';

Future<ChangePinUseCase> _setUp() async {
  final vaultRepo = InMemoryVaultRepository();
  final secureRepo = InMemorySecureStorageRepository();
  final session = VaultSession();
  final kdf = Pbkdf2KdfService(iterations: 1000);
  final crypto = AesGcmCryptoService();
  await CreateVaultUseCase(
    cryptoService: crypto,
    kdfService: kdf,
    vaultRepository: vaultRepo,
    secureStorageRepository: secureRepo,
    vaultSession: session,
    backupRepositories: [_NoopVmkBackupRepository()],
  ).execute(pin: _currentPin, mode: UserMode.localOnly);
  return ChangePinUseCase(
    vaultRepository: vaultRepo,
    secureStorageRepository: secureRepo,
    kdfService: kdf,
    cryptoService: crypto,
    vaultSession: session,
  );
}

Future<void> _type(WidgetTester tester, String pin) async {
  for (final d in pin.split('')) {
    await tester.tap(find.text(d).last);
    await tester.pump();
  }
  // Let the async verify (PBKDF2 off the fake clock) settle.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 200)),
  );
  await tester.pump();
}

void main() {
  group('ChangePinUseCase.verifyOldPin', () {
    test('accepts the current PIN and rejects others', () async {
      final useCase = await _setUp();
      expect(await useCase.verifyOldPin(_currentPin), isTrue);
      expect(await useCase.verifyOldPin('9135'), isFalse);
    });

    test('execute still changes the PIN after refactor', () async {
      final useCase = await _setUp();
      await useCase.execute(oldPin: _currentPin, newPin: '9135');
      expect(await useCase.verifyOldPin('9135'), isTrue);
      expect(await useCase.verifyOldPin(_currentPin), isFalse);
    });
  });

  group('ChangePinScreen', () {
    late ChangePinUseCase useCase;

    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async => useCase = await _setUp());
      await tester.pumpWidget(
        MaterialApp(
          home: ChangePinScreen(
            changePinUseCase: useCase,
            pinValidator: PinValidator(),
          ),
        ),
      );
    }

    testWidgets('shows a 3-step indicator starting at step 1', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.text('Enter current PIN'), findsOneWidget);
    });

    testWidgets('a wrong current PIN is rejected at step 1', (tester) async {
      await pumpScreen(tester);
      await _type(tester, '9135');
      expect(find.text('Step 1 of 3'), findsOneWidget);
      expect(find.textContaining("not your current PIN"), findsOneWidget);
    });

    testWidgets('new PIN equal to the current one is rejected', (tester) async {
      await pumpScreen(tester);
      await _type(tester, _currentPin);
      expect(find.text('Step 2 of 3'), findsOneWidget);
      await _type(tester, _currentPin);
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.textContaining('must be different'), findsOneWidget);
    });

    testWidgets('a confirm mismatch stays on step 3', (tester) async {
      await pumpScreen(tester);
      await _type(tester, _currentPin);
      await _type(tester, '9135');
      expect(find.text('Step 3 of 3'), findsOneWidget);
      await _type(tester, '9136');
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.textContaining("don't match"), findsOneWidget);
      expect(find.text('Choose a different new PIN'), findsOneWidget);
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
