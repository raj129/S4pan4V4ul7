import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;

import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/chat_backup_store.dart';

/// Keeps the chat backup in the user's Google Drive app-data folder, which is
/// private to this app and survives uninstalling or clearing data.
class GoogleDriveChatBackupStore implements ChatBackupStore {
  GoogleDriveChatBackupStore({required AuthRepository authRepository})
    : _authRepository = authRepository;

  final AuthRepository _authRepository;

  @override
  String get label => 'Google Drive';

  @override
  bool get requiresNetwork => true;

  static String _fileName(String accountId) => 'chat_backup_$accountId.enc';

  Future<drive.DriveApi> _api(bool interactive) async {
    final client = await _authRepository.getAuthenticatedClient(
      interactive: interactive,
    );
    if (client == null) {
      throw StateError('Google Drive is not authorised.');
    }
    return drive.DriveApi(client);
  }

  Future<drive.File?> _find(drive.DriveApi api, String accountId) async {
    final response = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '${_fileName(accountId)}'",
      $fields: 'files(id, name)',
    );
    final files = response.files;
    return (files == null || files.isEmpty) ? null : files.first;
  }

  @override
  Future<void> write(
    String accountId,
    Uint8List blob, {
    bool interactive = false,
  }) async {
    final api = await _api(interactive);
    final existing = await _find(api, accountId);
    final media = drive.Media(Stream.value(blob), blob.length);
    if (existing != null) {
      await api.files.update(drive.File(), existing.id!, uploadMedia: media);
    } else {
      await api.files.create(
        drive.File()
          ..name = _fileName(accountId)
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    }
  }

  @override
  Future<Uint8List?> read(
    String accountId, {
    bool interactive = false,
  }) async {
    final api = await _api(interactive);
    final existing = await _find(api, accountId);
    if (existing == null) return null;
    final media =
        await api.files.get(
              existing.id!,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}
