import 'dart:convert';
import 'dart:io';
import 'package:external_path/external_path.dart';
import 'package:path/path.dart' as p;
import '../../crypto/models/encrypted_payload.dart';
import '../../crypto/models/wrapped_key.dart';
import '../../crypto/services/crypto_service.dart';
import '../../domain/entities/vault_photo.dart';
import '../services/vault_session.dart';

class ExportPhotoUseCase {
  const ExportPhotoUseCase({
    required CryptoService cryptoService,
    required VaultSession vaultSession,
  })  : _cryptoService = cryptoService,
        _vaultSession = vaultSession;

  final CryptoService _cryptoService;
  final VaultSession _vaultSession;

  Future<String> execute(VaultPhoto photo) async {
    final plainBytes = await decryptToBytes(photo);

    // Save to Downloads.
    final downloadsPath = await ExternalPath.getExternalStoragePublicDirectory(
      ExternalPath.DIRECTORY_DOWNLOAD,
    );
    final exportDir = Directory(p.join(downloadsPath, 'PhotoVault_Exports'));
    if (!await exportDir.exists()) {
      await exportDir.create(recursive: true);
    }

    String exportPath = p.join(exportDir.path, photo.originalFilename);

    // Handle file name collisions
    int count = 1;
    final extension = p.extension(photo.originalFilename);
    final nameWithoutExt = p.basenameWithoutExtension(photo.originalFilename);
    while (await File(exportPath).exists()) {
      exportPath = p.join(exportDir.path, '${nameWithoutExt}_$count$extension');
      count++;
    }

    final exportFile = File(exportPath);
    await exportFile.writeAsBytes(plainBytes);

    return exportPath;
  }

  /// Decrypt a vault photo into memory.
  ///
  /// Split out of [execute] so callers that need the bytes — sending a vault
  /// photo as a chat attachment — do not have to write the plaintext to the
  /// public Downloads folder first.
  Future<List<int>> decryptToBytes(VaultPhoto photo) async {
    final vmk = _vaultSession.requireVmk();

    // 1. Parse wrapped DEK
    final dekMap = jsonDecode(photo.wrappedDek) as Map<String, dynamic>;
    final wrappedDek = WrappedKey(
      keyId: dekMap['keyId'] as String,
      wrappedBytes: base64Decode(dekMap['wrappedBytes'] as String),
      nonce: base64Decode(dekMap['nonce'] as String),
      mac: base64Decode(dekMap['mac'] as String),
      encryptionVersion: dekMap['encryptionVersion'] as int,
    );

    // 2. Unwrap DEK
    final aadDek = utf8.encode('${photo.id}:dek:v${photo.encryptionVersion}');
    final dek = await _cryptoService.unwrapKey(wrappedDek, vmk, aad: aadDek);

    try {
      // 3. Read encrypted payload
      final file = File(photo.encryptedFilePath);
      if (!await file.exists()) {
        throw Exception('Encrypted photo file not found.');
      }

      final raw = await file.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final payload = EncryptedPayload(
        nonce: base64Decode(decoded['nonce'] as String),
        cipherText: base64Decode(decoded['cipherText'] as String),
        mac: base64Decode(decoded['mac'] as String),
        encryptionVersion: decoded['encryptionVersion'] as int,
      );

      // 4. Decrypt photo
      final aadPhoto = utf8.encode(
        '${photo.id}:photo:v${photo.encryptionVersion}',
      );
      return await _cryptoService.decrypt(payload, dek, aad: aadPhoto);
    } finally {
      // Zero DEK
      try {
        dek.fillRange(0, dek.length, 0);
      } catch (_) {}
    }
  }
}
