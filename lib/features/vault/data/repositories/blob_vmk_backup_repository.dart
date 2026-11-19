import 'dart:convert';
import 'dart:typed_data';

import 'package:photo_vault/features/backup/domain/backup_blob_store.dart';
import '../../domain/repositories/vmk_backup_repository.dart';

/// Shared JSON-backed [VmkBackupRepository] implementation over [BackupByteStore].
///
/// Unifies local recovery-folder and Google Drive appDataFolder VMK persistence
/// so both get atomic writes, legacy path fallback, non-trashed newest-first
/// Drive resolution, duplicate cleanup, and resilient JSON validation.
abstract class BlobVmkBackupRepository implements VmkBackupRepository {
  const BlobVmkBackupRepository({
    required BackupByteStore store,
    required String fileName,
  }) : _store = store,
       _fileName = fileName;

  final BackupByteStore _store;
  final String _fileName;

  static Map<String, dynamic> _decodeMap(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('Corrupt VMK backup payload.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> backupVmk({
    required String vaultId,
    required Map<String, String> payload,
    bool interactive = false,
  }) async {
    var data = <String, dynamic>{};
    final existing = await _store.readBytes(_fileName, interactive: interactive);
    if (existing != null) {
      try {
        data = _decodeMap(existing);
      } catch (_) {
        // Heal corrupt JSON on write while preserving valid entries otherwise.
        data = <String, dynamic>{};
      }
    }
    data[vaultId] = payload;
    await _store.writeBytes(
      _fileName,
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      interactive: interactive,
    );
  }

  @override
  Future<Map<String, String>?> restoreVmk(
    String vaultId, {
    bool interactive = false,
  }) async {
    final bytes = await _store.readBytes(_fileName, interactive: interactive);
    if (bytes == null) return null;
    final data = _decodeMap(bytes);
    final rawPayload = data[vaultId];
    if (rawPayload == null) return null;
    if (rawPayload is! Map) {
      throw const FormatException('Corrupt VMK entry format.');
    }
    return rawPayload.map(
      (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
    );
  }

  @override
  Future<bool> hasBackup(String vaultId, {bool interactive = false}) async {
    final bytes = await _store.readBytes(_fileName, interactive: interactive);
    if (bytes == null) return false;
    try {
      final data = _decodeMap(bytes);
      return data.containsKey(vaultId);
    } on FormatException {
      return false;
    }
  }

  @override
  Future<List<String>> listVaultIds({bool interactive = false}) async {
    final bytes = await _store.readBytes(_fileName, interactive: interactive);
    if (bytes == null) return const [];
    final data = _decodeMap(bytes);
    return data.keys.toList();
  }
}
