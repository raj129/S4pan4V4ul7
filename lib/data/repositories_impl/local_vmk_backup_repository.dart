import 'dart:convert';
import 'dart:io';
import 'package:external_path/external_path.dart';
import 'package:path/path.dart' as p;
import '../../domain/repositories/vmk_backup_repository.dart';

class LocalVmkBackupRepository implements VmkBackupRepository {
  static const String _folderName = 'PhotoVault_Recovery';
  static const String _fileName = 'vmk_recovery.json';

  Future<String> _getBackupPath() async {
    final documentsPath = await ExternalPath.getExternalStoragePublicDirectory(
      ExternalPath.DIRECTORY_DOCUMENTS,
    );
    final directory = Directory(p.join(documentsPath, _folderName));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return p.join(directory.path, _fileName);
  }

  @override
  Future<void> backupVmk({
    required String vaultId,
    required Map<String, String> payload,
  }) async {
    final path = await _getBackupPath();
    final file = File(path);
    
    // We store it as a JSON map indexed by vaultId to support multiple vaults if needed
    Map<String, dynamic> data = {};
    if (await file.exists()) {
      try {
        data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        // Corrupted file, start fresh
      }
    }
    
    data[vaultId] = payload;
    await file.writeAsString(jsonEncode(data));
  }

  @override
  Future<Map<String, String>?> restoreVmk(String vaultId) async {
    final path = await _getBackupPath();
    final file = File(path);
    if (!await file.exists()) return null;

    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final payload = data[vaultId];
      if (payload != null) {
        return Map<String, String>.from(payload as Map);
      }
    } catch (_) {
      // Error reading or parsing
    }
    return null;
  }

  @override
  Future<bool> hasBackup(String vaultId) async {
    final path = await _getBackupPath();
    final file = File(path);
    if (!await file.exists()) return false;
    
    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return data.containsKey(vaultId);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<String>> listVaultIds() async {
    final path = await _getBackupPath();
    final file = File(path);
    if (!await file.exists()) return [];

    try {
      final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return data.keys.toList();
    } catch (_) {
      return [];
    }
  }
}
