import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_auth_repository.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import 'package:photo_vault/features/vault/application/services/restore_flow_service.dart';
import 'package:photo_vault/features/vault/application/usecases/restore_vault_usecase.dart';
import 'package:photo_vault/features/vault/presentation/screens/restore/restore_flow_screen.dart';

class _FakeRestoreFlowService implements RestoreFlowService {
  _FakeRestoreFlowService({
    this.vaultIds = const [],
    this.activeId,
    this.photoSummary = const RestorePhotosSummary(
      foundBackup: false,
      restored: 0,
      alreadyPresent: 0,
      unavailable: 0,
    ),
    this.listFailure,
    this.restoreFailure,
  });

  final List<String> vaultIds;
  final String? activeId;
  final RestorePhotosSummary photoSummary;
  final Object? listFailure;
  final Object? restoreFailure;
  String? restoredVaultId;
  String? usedOriginalPin;
  String? usedNewPin;
  int restoreCalls = 0;
  int photoRestoreCalls = 0;

  @override
  Future<String?> activeVaultId() async => activeId;

  @override
  Future<int> restoreChat({
    required bool includeChat,
    void Function(ChatRestoreProgress)? onProgress,
  }) async => 0;

  @override
  Future<void> skipChatRestore() async {}

  @override
  Future<List<String>> listVaultIds() async {
    final failure = listFailure;
    if (failure != null) throw failure;
    return vaultIds;
  }

  @override
  Future<void> restoreVault({
    required String vaultId,
    required String originalPin,
    required String newPin,
  }) async {
    restoreCalls++;
    final failure = restoreFailure;
    if (failure != null) throw failure;
    restoredVaultId = vaultId;
    usedOriginalPin = originalPin;
    usedNewPin = newPin;
  }

  @override
  Future<RestorePhotosSummary> restorePhotos({
    required bool includePhotos,
  }) async {
    photoRestoreCalls++;
    return photoSummary;
  }
}

Finder _pinField(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _enterPins(WidgetTester tester) async {
  await tester.ensureVisible(_pinField('PIN from backup time'));
  await tester.enterText(_pinField('PIN from backup time'), '1357');
  await tester.ensureVisible(_pinField('New app PIN for this device'));
  await tester.enterText(_pinField('New app PIN for this device'), '2468');
  await tester.ensureVisible(_pinField('Confirm PIN'));
  await tester.enterText(_pinField('Confirm PIN'), '2468');
}

void main() {
  testWidgets(
    'restores the selected vault and optionally restores photos before opening it',
    (tester) async {
      final service = _FakeRestoreFlowService(
        vaultIds: const ['original-vault-1234'],
        photoSummary: const RestorePhotosSummary(
          foundBackup: true,
          restored: 2,
          alreadyPresent: 0,
          unavailable: 0,
        ),
      );
      String? openedVaultId;
      await tester.pumpWidget(
        MaterialApp(
          home: RestoreFlowScreen(
            authRepository: InMemoryAuthRepository(defaultSignedIn: true),
            restoreFlowService: service,
            onRestoreCompleted: (vaultId) async {
              openedVaultId = vaultId;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Vault original…'), findsOneWidget);
      await _enterPins(tester);
      await tester.ensureVisible(find.text('Restore vault'));
      await tester.tap(find.text('Restore vault'));
      await tester.pumpAndSettle();

      expect(service.restoredVaultId, 'original-vault-1234');
      expect(service.usedOriginalPin, '1357');
      expect(service.usedNewPin, '2468');
      expect(service.photoRestoreCalls, 1);
      expect(
        find.textContaining('vault photo restore is running in the background'),
        findsOneWidget,
      );

      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to chat'));
      await tester.pumpAndSettle();
      expect(openedVaultId, 'original-vault-1234');
    },
  );

  testWidgets('asks before switching to a different vault and keeps old data', (
    tester,
  ) async {
    final service = _FakeRestoreFlowService(
      vaultIds: const ['current-vault-111', 'target-vault-222'],
      activeId: 'current-vault-111',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RestoreFlowScreen(
          authRepository: InMemoryAuthRepository(defaultSignedIn: true),
          restoreFlowService: service,
          onRestoreCompleted: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Vault target-v…'));
    await tester.tap(find.text('Vault target-v…'));
    await tester.pumpAndSettle();
    await _enterPins(tester);
    await tester.ensureVisible(find.text('Restore vault'));
    await tester.tap(find.text('Restore vault'));
    await tester.pumpAndSettle();

    expect(find.text('Switch active vault?'), findsOneWidget);
    expect(find.textContaining('will not be deleted'), findsOneWidget);
    await tester.tap(find.text('Switch vault'));
    await tester.pumpAndSettle();

    expect(service.restoredVaultId, 'target-vault-222');
    expect(find.text('Continue to chat'), findsOneWidget);
  });

  testWidgets('reports a wrong original PIN without restoring photos', (
    tester,
  ) async {
    final service = _FakeRestoreFlowService(
      vaultIds: const ['original-vault-1234'],
      restoreFailure: const VaultBackupPinException(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: RestoreFlowScreen(
          authRepository: InMemoryAuthRepository(defaultSignedIn: true),
          restoreFlowService: service,
          onRestoreCompleted: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _enterPins(tester);
    await tester.ensureVisible(find.text('Restore vault'));
    await tester.tap(find.text('Restore vault'));
    await tester.pumpAndSettle();

    expect(service.restoreCalls, 1);
    expect(find.textContaining('original PIN could not open'), findsOneWidget);
    expect(service.photoRestoreCalls, 0);
    expect(find.text('Open vault'), findsNothing);
  });

  testWidgets('distinguishes no available vault backups', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RestoreFlowScreen(
          authRepository: InMemoryAuthRepository(defaultSignedIn: true),
          restoreFlowService: _FakeRestoreFlowService(),
          onRestoreCompleted: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No vault backups were found for this account.'),
      findsOneWidget,
    );
    expect(find.text('Google mode & restore'), findsNothing);
  });

  testWidgets('shows an actionable message when Google Drive API is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RestoreFlowScreen(
          authRepository: InMemoryAuthRepository(defaultSignedIn: true),
          restoreFlowService: _FakeRestoreFlowService(
            listFailure: StateError(
              'DetailedApiRequestError(status: 403, message: '
              'Google Drive API has not been used in project 209716874258)',
            ),
          ),
          onRestoreCompleted: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Google Drive API is disabled'), findsOneWidget);
    expect(find.textContaining('Enable drive.googleapis.com'), findsOneWidget);
  });
}
