import 'dart:io';
import 'dart:typed_data';

import 'package:googleapis/drive/v3.dart' as drive;

import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import '../domain/backup_blob_store.dart';

/// Keeps blobs in the user's Google Drive app-data folder, private to this
/// app and kept across uninstall or cleared data.
class DriveBackupBlobStore implements BackupByteStore {
  DriveBackupBlobStore({required AuthRepository authRepository})
    : _authRepository = authRepository;

  final AuthRepository _authRepository;

  @override
  String get label => 'Google Drive';

  @override
  bool get isCloud => true;

  @override
  bool get requiresNetwork => true;

  Future<drive.DriveApi> _api(bool interactive) async {
    final client = await _authRepository.getAuthenticatedClient(
      interactive: interactive,
    );
    if (client == null) {
      throw StateError('Google Drive is not authorised.');
    }
    return drive.DriveApi(client);
  }

  /// Drive names are matched exactly, so quotes in [name] must be escaped.
  static String _quote(String name) =>
      "'${name.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}'";

  /// All app-data files with this exact name, newest first. Concurrent creates
  /// can leave duplicates, so every match is considered.
  Future<List<drive.File>> _findAll(drive.DriveApi api, String name) async {
    final response = await api.files.list(
      spaces: 'appDataFolder',
      q: 'name = ${_quote(name)} and trashed = false',
      $fields: 'files(id, name, modifiedTime)',
    );
    final files = [...?response.files]
      ..sort(
        (a, b) => (b.modifiedTime ?? DateTime(0)).compareTo(
          a.modifiedTime ?? DateTime(0),
        ),
      );
    return files;
  }

  @override
  Future<void> writeFile(
    String name,
    File source, {
    bool interactive = false,
  }) async {
    final api = await _api(interactive);
    final matches = await _findAll(api, name);
    final length = await source.length();
    // Streamed from disk, so a large photo is never held in memory.
    final media = drive.Media(source.openRead(), length);
    if (matches.isNotEmpty) {
      await api.files.update(
        drive.File(),
        matches.first.id!,
        uploadMedia: media,
      );
      for (final extra in matches.skip(1)) {
        await api.files.delete(extra.id!);
      }
    } else {
      await api.files.create(
        drive.File()
          ..name = name
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    }
  }

  @override
  Future<bool> readToFile(
    String name,
    File destination, {
    bool interactive = false,
  }) async {
    final api = await _api(interactive);
    final matches = await _findAll(api, name);
    if (matches.isEmpty) return false;
    final media =
        await api.files.get(
              matches.first.id!,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final sink = destination.openWrite();
    try {
      await sink.addStream(media.stream);
    } finally {
      await sink.close();
    }
    return true;
  }

  @override
  Future<void> writeBytes(
    String name,
    Uint8List bytes, {
    bool interactive = false,
  }) async {
    final api = await _api(interactive);
    final matches = await _findAll(api, name);
    final media = drive.Media(Stream.value(bytes), bytes.length);
    if (matches.isNotEmpty) {
      await api.files.update(
        drive.File(),
        matches.first.id!,
        uploadMedia: media,
      );
      for (final extra in matches.skip(1)) {
        await api.files.delete(extra.id!);
      }
    } else {
      await api.files.create(
        drive.File()
          ..name = name
          ..parents = ['appDataFolder'],
        uploadMedia: media,
      );
    }
  }

  @override
  Future<Uint8List?> readBytes(String name, {bool interactive = false}) async {
    final api = await _api(interactive);
    final matches = await _findAll(api, name);
    if (matches.isEmpty) return null;
    final media =
        await api.files.get(
              matches.first.id!,
              downloadOptions: drive.DownloadOptions.fullMedia,
            )
            as drive.Media;
    final builder = BytesBuilder(copy: false);
    await for (final chunk in media.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  @override
  Future<List<String>> list(String prefix, {bool interactive = false}) async {
    final api = await _api(interactive);
    final names = <String>[];
    String? pageToken;
    do {
      final response = await api.files.list(
        spaces: 'appDataFolder',
        q: "name contains ${_quote(prefix)} and trashed = false",
        $fields: 'nextPageToken, files(name)',
        pageSize: 100,
        pageToken: pageToken,
      );
      for (final file in response.files ?? const <drive.File>[]) {
        final name = file.name;
        if (name != null && name.startsWith(prefix)) names.add(name);
      }
      pageToken = response.nextPageToken;
    } while (pageToken != null);
    return names;
  }

  @override
  Future<void> delete(String name, {bool interactive = false}) async {
    final api = await _api(interactive);
    for (final file in await _findAll(api, name)) {
      await api.files.delete(file.id!);
    }
  }
}
