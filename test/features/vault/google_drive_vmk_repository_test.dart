import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/google_drive_vmk_repository.dart';

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
}
