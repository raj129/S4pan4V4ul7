import 'dart:convert';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/vmk_backup_repository.dart';

class GoogleDriveVmkRepository implements VmkBackupRepository {
  GoogleDriveVmkRepository({required AuthRepository authRepository})
      : _authRepository = authRepository;

  final AuthRepository _authRepository;
  static const String _fileName = 'vmk_backup.json';

  Future<drive.DriveApi?> _getDriveApi() async {
    final client = await _authRepository.getAuthenticatedClient();
    if (client == null) return null;
    return drive.DriveApi(client);
  }

  Future<drive.File?> _findBackupFile(drive.DriveApi api) async {
    final response = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$_fileName'",
      $fields: 'files(id, name)',
    );
    final files = response.files;
    if (files == null || files.isEmpty) return null;
    return files.first;
  }

  @override
  Future<void> backupVmk({
    required String vaultId,
    required Map<String, String> payload,
  }) async {
    final api = await _getDriveApi();
    if (api == null) throw Exception('Not authenticated with Google');

    final existingFile = await _findBackupFile(api);
    
    Map<String, dynamic> data = {};
    if (existingFile != null) {
      final media = await api.files.get(
        existingFile.id!,
        downloadOptions: drive.DownloadOptions.metadata,
      ) as drive.Media; // Wait, drive.DownloadOptions.fullMedia is needed
      
      // Correct way to download
      final drive.Media download = await api.files.get(
        existingFile.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      
      final content = await utf8.decodeStream(download.stream);
      data = jsonDecode(content) as Map<String, dynamic>;
    }

    data[vaultId] = payload;
    final bytes = utf8.encode(jsonEncode(data));
    final media = drive.Media(Stream.value(bytes), bytes.length);

    if (existingFile != null) {
      await api.files.update(
        drive.File(),
        existingFile.id!,
        uploadMedia: media,
      );
    } else {
      final fileToCreate = drive.File()
        ..name = _fileName
        ..parents = ['appDataFolder'];
      await api.files.create(
        fileToCreate,
        uploadMedia: media,
      );
    }
  }

  @override
  Future<Map<String, String>?> restoreVmk(String vaultId) async {
    final api = await _getDriveApi();
    if (api == null) return null;

    final existingFile = await _findBackupFile(api);
    if (existingFile == null) return null;

    final drive.Media download = await api.files.get(
      existingFile.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final content = await utf8.decodeStream(download.stream);
    final data = jsonDecode(content) as Map<String, dynamic>;
    final payload = data[vaultId];
    if (payload != null) {
      return Map<String, String>.from(payload as Map);
    }
    return null;
  }

  @override
  Future<bool> hasBackup(String vaultId) async {
    final api = await _getDriveApi();
    if (api == null) return false;

    final existingFile = await _findBackupFile(api);
    if (existingFile == null) return false;
    
    // To be sure the vaultId is inside, we might need to download or trust filename if it was per vaultId
    // But since we aggregate, we have to download.
    final drive.Media download = await api.files.get(
      existingFile.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final content = await utf8.decodeStream(download.stream);
    final data = jsonDecode(content) as Map<String, dynamic>;
    return data.containsKey(vaultId);
  }

  @override
  Future<List<String>> listVaultIds() async {
    final api = await _getDriveApi();
    if (api == null) return [];

    final existingFile = await _findBackupFile(api);
    if (existingFile == null) return [];

    final drive.Media download = await api.files.get(
      existingFile.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;

    final content = await utf8.decodeStream(download.stream);
    final data = jsonDecode(content) as Map<String, dynamic>;
    return data.keys.toList();
  }
}
