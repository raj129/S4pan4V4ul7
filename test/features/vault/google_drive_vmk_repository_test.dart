import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/google_drive_vmk_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/local_vmk_backup_repository.dart';

class _MemoryAuthRepository implements AuthRepository {
  _MemoryAuthRepository(this.client);

  final http.Client? client;

  @override
  Future<http.Client?> getAuthenticatedClient({
    bool interactive = false,
  }) async => client;

  @override
  Future<void> signOut() async {}

  @override
  Future<AuthResult> signInWithGoogle() async =>
      const AuthResult(userId: 'user', email: 'user@example.com');

  @override
  Future<bool> isSignedIn() async => client != null;

  @override
  Future<void> warmUpDriveAuthorization({bool interactive = false}) async {}
}

class _DriveApiClient extends http.BaseClient {
  _DriveApiClient(this.backups);

  final Map<String, Map<String, String>> backups;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    if (path.endsWith('/drive/v3/files')) {
      return _jsonResponse({
        'files': [
          {'id': 'vmk-file', 'name': 'vmk_backup.json'},
        ],
      });
    }
    if (path.endsWith('/drive/v3/files/vmk-file')) {
      return http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(backups))),
        200,
        headers: const {'content-type': 'application/json'},
      );
    }
    return _jsonResponse({'error': 'not found'}, status: 404);
  }

  http.StreamedResponse _jsonResponse(Object body, {int status = 200}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: const {'content-type': 'application/json'},
      );
}

void main() {
  test(
    'lists and restores the selected vault from the Drive envelope',
    () async {
      final client = _DriveApiClient({
        'vault-a': {'wrappedVmk': 'a'},
        'vault-b': {'wrappedVmk': 'b', 'encVersion': '1'},
      });
      final repository = GoogleDriveVmkRepository(
        authRepository: _MemoryAuthRepository(client),
      );

      expect(await repository.listVaultIds(interactive: true), [
        'vault-a',
        'vault-b',
      ]);
      expect(await repository.restoreVmk('vault-b', interactive: true), {
        'wrappedVmk': 'b',
        'encVersion': '1',
      });
      client.close();
    },
  );

  test('reports missing Drive authorization instead of no backup', () async {
    final repository = GoogleDriveVmkRepository(
      authRepository: _MemoryAuthRepository(null),
    );

    await expectLater(
      repository.listVaultIds(interactive: true),
      throwsA(isA<StateError>()),
    );
  });

  test('LocalVmkBackupRepository backs up, lists, and heals corrupt JSON', () async {
    final dir = await Directory.systemTemp.createTemp('local_vmk_test');
    addTearDown(() => dir.delete(recursive: true));
    final repo = LocalVmkBackupRepository(baseDirectory: () async => dir);

    await repo.backupVmk(
      vaultId: 'vault-1',
      payload: const {'wrappedVmk': 'k1'},
    );
    expect(await repo.listVaultIds(), ['vault-1']);
    expect(await repo.restoreVmk('vault-1'), {'wrappedVmk': 'k1'});

    // Corrupting the file surfaces FormatException on list/restore rather than
    // silently claiming no backup, returns false from hasBackup, and heals on write.
    await File(
      '${dir.path}/PhotoVault_Recovery/vmk_recovery.json',
    ).writeAsString('{corrupt-json');
    await expectLater(repo.listVaultIds(), throwsFormatException);
    expect(await repo.hasBackup('vault-1'), isFalse);
    await repo.backupVmk(
      vaultId: 'vault-2',
      payload: const {'wrappedVmk': 'k2'},
    );
    expect(await repo.listVaultIds(), ['vault-2']);
  });
}
