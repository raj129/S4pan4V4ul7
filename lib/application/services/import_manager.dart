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
  bool _useExternalStorageMirror = true;
  bool _driveEncryptedBackupEnabled = false;
  ImportJobProgress _progress = const ImportJobProgress(
    jobId: '',
    total: 0,
    completed: 0,
    status: ImportJobStatus.idle,
  );

  ImportJobProgress get progress => _progress;

  void configureStorage({
    required bool useExternalStorageMirror,
    required bool driveEncryptedBackupEnabled,
  }) {
    _useExternalStorageMirror = useExternalStorageMirror;
    _driveEncryptedBackupEnabled = driveEncryptedBackupEnabled;
  }

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

  Future<Uint8List?> loadPhotoBytes(VaultPhoto photo) async {
    final vmk = _vaultSession.requireVmk();
    final wrappedDek = _parseWrappedDek(photo.wrappedDek);
    final dek = await _cryptoService.unwrapKey(
      wrappedDek,
      vmk,
      aad: utf8.encode('${photo.id}:dek:v${photo.encryptionVersion}'),
    );
    try {
      final payload = await _readPayloadFile(photo.encryptedFilePath);
      final plain = await _cryptoService.decrypt(
        payload,
        dek,
        aad: utf8.encode('${photo.id}:photo:v${photo.encryptionVersion}'),
      );
      return Uint8List.fromList(plain);
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
        await Future<void>.delayed(Duration.zero);
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
          await _upsertExternalManifest(
            id: id,
            originalFilename: name,
            photoPath: photoPath,
            thumbPath: thumbPath,
            checksum: checksum,
            wrappedDekJson: _wrappedDekToJson(wrappedDek),
            photoNonce: base64Encode(encryptedPhoto.nonce),
            thumbNonce: base64Encode(encryptedThumb.nonce),
            encryptionVersion: _cryptoService.encryptionVersion,
            fileSize: fileSize,
            mimeType: _mimeFromFileName(name),
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

  /// Removes DB records that point to missing encrypted files.
  Future<int> reconcileVaultFiles() async {
    var page = 0;
    var removed = 0;
    while (true) {
      final rows = await _photoRepository.listGalleryPage(
        page: page,
        pageSize: 500,
      );
      if (rows.isEmpty) break;
      for (final photo in rows) {
        final hasPhoto = await File(photo.encryptedFilePath).exists();
        final hasThumb = await File(photo.thumbnailPath).exists();
        if (!hasPhoto || !hasThumb) {
          await _photoRepository.permanentlyDelete(photo.id);
          removed += 1;
        }
      }
      page += 1;
    }
    return removed;
  }

  Future<String> _writePayloadFile({
    required String id,
    required String kind,
    required EncryptedPayload payload,
  }) async {
    final vaultRoot = await _resolveVaultRoot();
    final vaultDir = Directory(p.join(vaultRoot.path, 'objects'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }
    final filePath = p.join(vaultDir.path, '$id.$kind.enc');
    final file = File(filePath);
    await file.writeAsString(jsonEncode(_payloadToJson(payload)), flush: true);
    return filePath;
  }

  Future<Directory> _resolveVaultRoot() async {
    if (!_useExternalStorageMirror || !Platform.isAndroid) {
      final baseDir = await getApplicationSupportDirectory();
      return Directory(p.join(baseDir.path, 'vault'));
    }
    final external = await getExternalStorageDirectory();
    if (external == null) {
      final baseDir = await getApplicationSupportDirectory();
      return Directory(p.join(baseDir.path, 'vault'));
    }

    final marker =
        '${Platform.pathSeparator}Android${Platform.pathSeparator}data${Platform.pathSeparator}';
    final extPath = external.path;
    if (extPath.contains(marker)) {
      final split = extPath.split(marker);
      final packageAndRest = split[1];
      final packageName = packageAndRest.split(Platform.pathSeparator).first;
      final mediaRoot = Directory(
        p.join(
          split[0],
          'Android',
          'media',
          packageName,
          'vault',
        ),
      );
      if (!await mediaRoot.exists()) {
        await mediaRoot.create(recursive: true);
      }
      return mediaRoot;
    }

    final fallback = Directory(p.join(external.path, 'vault'));
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    return fallback;
  }

  Future<void> _upsertExternalManifest({
    required String id,
    required String originalFilename,
    required String photoPath,
    required String thumbPath,
    required String checksum,
    required String wrappedDekJson,
    required String photoNonce,
    required String thumbNonce,
    required int encryptionVersion,
    required int fileSize,
    required String mimeType,
  }) async {
    if (!_useExternalStorageMirror) return;
    final root = await _resolveVaultRoot();
    final manifestDir = Directory(p.join(root.path, 'manifest'));
    if (!await manifestDir.exists()) {
      await manifestDir.create(recursive: true);
    }
    final manifestFile = File(p.join(manifestDir.path, 'manifest.json'));
    Map<String, dynamic> doc = <String, dynamic>{'version': 1, 'photos': {}};
    if (await manifestFile.exists()) {
      try {
        final parsed = jsonDecode(await manifestFile.readAsString());
        if (parsed is Map<String, dynamic>) {
          doc = parsed;
        }
      } catch (_) {}
    }
    final photosMap = (doc['photos'] as Map?)?.cast<String, dynamic>() ??
        <String, dynamic>{};
    photosMap[id] = <String, dynamic>{
      'id': id,
      'originalFilename': originalFilename,
      'encryptedFilePath': photoPath,
      'thumbnailPath': thumbPath,
      'checksumSha256': checksum,
      'wrappedDek': wrappedDekJson,
      'photoNonce': photoNonce,
      'thumbnailNonce': thumbNonce,
      'encryptionVersion': encryptionVersion,
      'fileSize': fileSize,
      'mimeType': mimeType,
      'driveUploadRequested': _driveEncryptedBackupEnabled,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    doc['photos'] = photosMap;
    await manifestFile.writeAsString(jsonEncode(doc), flush: true);
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
