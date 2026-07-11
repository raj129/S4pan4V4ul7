import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../crypto/models/encrypted_payload.dart';
import '../../crypto/models/wrapped_key.dart';
import '../../crypto/services/crypto_service.dart';
import '../../domain/entities/vault_photo.dart';
import '../../domain/repositories/photo_repository.dart';
import 'vault_session.dart';

enum ImportJobStatus { idle, running, completed, failed }

class ImportJobProgress {
  const ImportJobProgress({
    required this.jobId,
    required this.total,
    required this.completed,
    required this.status,
    this.errorMessage,
  });

  final String jobId;
  final int total;
  final int completed;
  final ImportJobStatus status;
  final String? errorMessage;

  double get ratio => total == 0 ? 0 : completed / total;
}

class ImportManager extends ChangeNotifier {
  ImportManager({
    required PhotoRepository photoRepository,
    required CryptoService cryptoService,
    required VaultSession vaultSession,
  }) : _photoRepository = photoRepository,
       _cryptoService = cryptoService,
       _vaultSession = vaultSession;

  final PhotoRepository _photoRepository;
  final CryptoService _cryptoService;
  final VaultSession _vaultSession;
  final _sha256 = Sha256();
  static const _uuid = Uuid();
  final List<XFile> _pendingShareFiles = [];
  final Map<String, Uint8List> _thumbnailMemoryCache = {};
  ImportJobProgress _progress = const ImportJobProgress(
    jobId: '',
    total: 0,
    completed: 0,
    status: ImportJobStatus.idle,
  );

  ImportJobProgress get progress => _progress;

  List<XFile> takePendingShareFiles() {
    final copy = List<XFile>.from(_pendingShareFiles);
    _pendingShareFiles.clear();
    return copy;
  }

  void setPendingShareFiles(List<XFile> files) {
    _pendingShareFiles
      ..clear()
      ..addAll(files);
    notifyListeners();
  }

  void clearPendingShareFiles() {
    _pendingShareFiles.clear();
    notifyListeners();
  }

  Future<Uint8List?> loadThumbnailBytes(VaultPhoto photo) async {
    final cached = _thumbnailMemoryCache[photo.id];
    if (cached != null) {
      return cached;
    }
    final vmk = _vaultSession.requireVmk();
    final wrappedDek = _parseWrappedDek(photo.wrappedDek);
    final dek = await _cryptoService.unwrapKey(
      wrappedDek,
      vmk,
      aad: utf8.encode('${photo.id}:dek:v${photo.encryptionVersion}'),
    );
    try {
      final payload = await _readPayloadFile(photo.thumbnailPath);
      final plain = await _cryptoService.decrypt(
        payload,
        dek,
        aad: utf8.encode('${photo.id}:thumb:v${photo.encryptionVersion}'),
      );
      final bytes = Uint8List.fromList(plain);
      _thumbnailMemoryCache[photo.id] = bytes;
      return bytes;
    } finally {
      try {
        dek.fillRange(0, dek.length, 0);
      } catch (_) {}
    }
  }

  Future<void> enqueueImport({
    required List<XFile> files,
    required String source,
  }) async {
    if (files.isEmpty) return;
    final jobId = _uuid.v4();
    _progress = ImportJobProgress(
      jobId: jobId,
      total: files.length,
      completed: 0,
      status: ImportJobStatus.running,
    );
    notifyListeners();

    try {
      var completed = 0;
      final vmk = _vaultSession.requireVmk();
      for (final file in files) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final name = p.basename(file.path.isEmpty ? 'imported.jpg' : file.path);
        final fileSize = await file.length();
        final id = _uuid.v4();
        final plainBytes = await file.readAsBytes();
        final hashBytes = await _sha256.hash(plainBytes);
        final checksum = _toHex(hashBytes.bytes);
        final duplicate = await _photoRepository.existsChecksum(checksum);
        if (duplicate) {
          completed += 1;
          _progress = ImportJobProgress(
            jobId: jobId,
            total: files.length,
            completed: completed,
            status: ImportJobStatus.running,
          );
          notifyListeners();
          continue;
        }

        final dek = await _cryptoService.generateSymmetricKey();
        try {
          final encryptedPhoto = await _cryptoService.encrypt(
            plainBytes,
            dek,
            aad: utf8.encode('$id:photo:v${_cryptoService.encryptionVersion}'),
          );
          final encryptedThumb = await _cryptoService.encrypt(
            plainBytes,
            dek,
            aad: utf8.encode('$id:thumb:v${_cryptoService.encryptionVersion}'),
          );
          final wrappedDek = await _cryptoService.wrapKey(
            dek,
            vmk,
            keyId: id,
            aad: utf8.encode('$id:dek:v${_cryptoService.encryptionVersion}'),
          );

          final photoPath = await _writePayloadFile(
            id: id,
            kind: 'photo',
            payload: encryptedPhoto,
          );
          final thumbPath = await _writePayloadFile(
            id: id,
            kind: 'thumb',
            payload: encryptedThumb,
          );

          await _photoRepository.upsertPhoto(
            VaultPhoto(
              id: id,
              originalFilename: name,
              encryptedFilePath: photoPath,
              thumbnailPath: thumbPath,
              wrappedDek: _wrappedDekToJson(wrappedDek),
              photoNonce: base64Encode(encryptedPhoto.nonce),
              thumbnailNonce: base64Encode(encryptedThumb.nonce),
              encryptionVersion: _cryptoService.encryptionVersion,
              checksumSha256: checksum,
              fileSize: fileSize,
              mimeType: _mimeFromFileName(name),
              createdTimeMs: now,
              importedTimeMs: now,
              modifiedTimeMs: now,
              favorite: false,
              isTrashed: false,
            ),
          );
        } finally {
          try {
            dek.fillRange(0, dek.length, 0);
          } catch (_) {}
        }

        completed += 1;
        _progress = ImportJobProgress(
          jobId: jobId,
          total: files.length,
          completed: completed,
          status: ImportJobStatus.running,
        );
        notifyListeners();
      }
      _thumbnailMemoryCache.clear();

      _progress = ImportJobProgress(
        jobId: jobId,
        total: files.length,
        completed: files.length,
        status: ImportJobStatus.completed,
      );
      notifyListeners();
    } catch (e) {
      _progress = ImportJobProgress(
        jobId: jobId,
        total: files.length,
        completed: _progress.completed,
        status: ImportJobStatus.failed,
        errorMessage: 'Import failed.',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<String> _writePayloadFile({
    required String id,
    required String kind,
    required EncryptedPayload payload,
  }) async {
    final baseDir = await getApplicationSupportDirectory();
    final vaultDir = Directory(p.join(baseDir.path, 'vault', 'objects'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    final filePath = p.join(vaultDir.path, '$id.$kind.enc');
    final file = File(filePath);
    await file.writeAsString(jsonEncode(_payloadToJson(payload)), flush: true);
    return filePath;
  }

  Future<EncryptedPayload> _readPayloadFile(String filePath) async {
    final file = File(filePath);
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return EncryptedPayload(
      nonce: base64Decode(decoded['nonce'] as String),
      cipherText: base64Decode(decoded['cipherText'] as String),
      mac: base64Decode(decoded['mac'] as String),
      encryptionVersion: decoded['encryptionVersion'] as int,
    );
  }

  Map<String, dynamic> _payloadToJson(EncryptedPayload payload) => {
    'nonce': base64Encode(payload.nonce),
    'cipherText': base64Encode(payload.cipherText),
    'mac': base64Encode(payload.mac),
    'encryptionVersion': payload.encryptionVersion,
  };

  String _wrappedDekToJson(WrappedKey wrapped) {
    final map = <String, dynamic>{
      'keyId': wrapped.keyId,
      'wrappedBytes': base64Encode(wrapped.wrappedBytes),
      'nonce': base64Encode(wrapped.nonce),
      'mac': base64Encode(wrapped.mac),
      'encryptionVersion': wrapped.encryptionVersion,
    };
    return jsonEncode(map);
  }

  WrappedKey _parseWrappedDek(String encoded) {
    final decoded = jsonDecode(encoded) as Map<String, dynamic>;
    return WrappedKey(
      keyId: decoded['keyId'] as String,
      wrappedBytes: base64Decode(decoded['wrappedBytes'] as String),
      nonce: base64Decode(decoded['nonce'] as String),
      mac: base64Decode(decoded['mac'] as String),
      encryptionVersion: decoded['encryptionVersion'] as int,
    );
  }

  String _toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  String _mimeFromFileName(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}
