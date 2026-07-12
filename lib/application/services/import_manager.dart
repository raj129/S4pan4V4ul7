import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
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
  static const _uuid = Uuid();

  final List<XFile> _pendingShareFiles = [];
  final Map<String, Uint8List> _thumbnailMemoryCache = {};
  Future<void> _jobQueue = Future<void>.value();
  bool _useExternalStorageMirror = true;
  bool _driveEncryptedBackupEnabled = false;
  String? _lastImportedPhotoId;
  int _galleryEventRevision = 0;
  ImportJobProgress _progress = const ImportJobProgress(
    jobId: '',
    total: 0,
    completed: 0,
    status: ImportJobStatus.idle,
  );

  ImportJobProgress get progress => _progress;
  String? get lastImportedPhotoId => _lastImportedPhotoId;
  int get galleryEventRevision => _galleryEventRevision;

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

  void startBackgroundImport({
    required List<XFile> files,
    required String source,
  }) {
    if (files.isEmpty) return;
    _jobQueue = _jobQueue.then(
      (_) => _runImportJob(files: files, source: source),
    );
    unawaited(_jobQueue);
  }

  Future<void> enqueueImport({
    required List<XFile> files,
    required String source,
  }) {
    if (files.isEmpty) {
      return Future<void>.value();
    }
    _jobQueue = _jobQueue.then(
      (_) => _runImportJob(files: files, source: source),
    );
    return _jobQueue;
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
      final thumbFile = File(photo.thumbnailPath);
      if (!await thumbFile.exists()) {
        final regenerated = await _regenerateThumbnail(photo: photo, dek: dek);
        _thumbnailMemoryCache[photo.id] = regenerated;
        return regenerated;
      }
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
        if (!hasPhoto) {
          await _photoRepository.deleteMetadataOnly(photo.id);
          await _removeManifestEntry(photo.id);
          _thumbnailMemoryCache.remove(photo.id);
          _lastImportedPhotoId = null;
          removed += 1;
          _galleryEventRevision += 1;
          notifyListeners();
          continue;
        }
        if (!hasThumb) {
          final vmk = _vaultSession.requireVmk();
          final wrappedDek = _parseWrappedDek(photo.wrappedDek);
          final dek = await _cryptoService.unwrapKey(
            wrappedDek,
            vmk,
            aad: utf8.encode('${photo.id}:dek:v${photo.encryptionVersion}'),
          );
          try {
            await _regenerateThumbnail(photo: photo, dek: dek);
          } finally {
            try {
              dek.fillRange(0, dek.length, 0);
            } catch (_) {}
          }
        }
      }
      page += 1;
    }
    return removed;
  }

  Future<void> _runImportJob({
    required List<XFile> files,
    required String source,
  }) async {
    final jobId = _uuid.v4();
    _progress = ImportJobProgress(
      jobId: jobId,
      total: files.length,
      completed: 0,
      status: ImportJobStatus.running,
    );
    notifyListeners();

    var completed = 0;
    final vmk = _vaultSession.requireVmk();
    try {
      for (final file in files) {
        try {
          final prepared = await Isolate.run(
            () => _prepareImportFile(file.path),
          );
          final checksum = prepared['checksumSha256'] as String;
          final duplicate = await _photoRepository.existsChecksum(checksum);
          if (!duplicate) {
            final now = DateTime.now().millisecondsSinceEpoch;
            final id = _uuid.v4();
            final plainBytes = prepared['photoBytes'] as Uint8List;
            final thumbnailBytes = prepared['thumbnailBytes'] as Uint8List;
            final fileSize = prepared['fileSize'] as int;
            final mimeType = prepared['mimeType'] as String;
            final originalFilename = prepared['originalFilename'] as String;

            final dek = await _cryptoService.generateSymmetricKey();
            try {
              final encryptedPhoto = await _cryptoService.encrypt(
                plainBytes,
                dek,
                aad: utf8.encode(
                  '$id:photo:v${_cryptoService.encryptionVersion}',
                ),
              );
              final encryptedThumb = await _cryptoService.encrypt(
                thumbnailBytes,
                dek,
                aad: utf8.encode(
                  '$id:thumb:v${_cryptoService.encryptionVersion}',
                ),
              );
              final wrappedDek = await _cryptoService.wrapKey(
                dek,
                vmk,
                keyId: id,
                aad: utf8.encode(
                  '$id:dek:v${_cryptoService.encryptionVersion}',
                ),
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
                  originalFilename: originalFilename,
                  encryptedFilePath: photoPath,
                  thumbnailPath: thumbPath,
                  wrappedDek: _wrappedDekToJson(wrappedDek),
                  photoNonce: base64Encode(encryptedPhoto.nonce),
                  thumbnailNonce: base64Encode(encryptedThumb.nonce),
                  encryptionVersion: _cryptoService.encryptionVersion,
                  checksumSha256: checksum,
                  fileSize: fileSize,
                  mimeType: mimeType,
                  createdTimeMs: now,
                  importedTimeMs: now,
                  modifiedTimeMs: now,
                  favorite: false,
                  isTrashed: false,
                ),
              );
              await _upsertExternalManifest(
                id: id,
                originalFilename: originalFilename,
                photoPath: photoPath,
                thumbPath: thumbPath,
                checksum: checksum,
                wrappedDekJson: _wrappedDekToJson(wrappedDek),
                photoNonce: base64Encode(encryptedPhoto.nonce),
                thumbNonce: base64Encode(encryptedThumb.nonce),
                encryptionVersion: _cryptoService.encryptionVersion,
                fileSize: fileSize,
                mimeType: mimeType,
                source: source,
              );
              _thumbnailMemoryCache[id] = thumbnailBytes;
              _lastImportedPhotoId = id;
              _galleryEventRevision += 1;
              notifyListeners();
            } finally {
              try {
                dek.fillRange(0, dek.length, 0);
              } catch (_) {}
            }
          }
        } catch (_) {
          // Keep the rest of the batch running; the job banner will still finish.
        }

        completed += 1;
        _progress = ImportJobProgress(
          jobId: jobId,
          total: files.length,
          completed: completed,
          status: ImportJobStatus.running,
        );
        notifyListeners();
        await Future<void>.delayed(Duration.zero);
      }

      _progress = ImportJobProgress(
        jobId: jobId,
        total: files.length,
        completed: files.length,
        status: ImportJobStatus.completed,
      );
      notifyListeners();
    } catch (_) {
      _progress = ImportJobProgress(
        jobId: jobId,
        total: files.length,
        completed: completed,
        status: ImportJobStatus.failed,
        errorMessage: 'Import failed.',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<Uint8List> _regenerateThumbnail({
    required VaultPhoto photo,
    required List<int> dek,
  }) async {
    final photoPayload = await _readPayloadFile(photo.encryptedFilePath);
    final plainPhoto = await _cryptoService.decrypt(
      photoPayload,
      dek,
      aad: utf8.encode('${photo.id}:photo:v${photo.encryptionVersion}'),
    );
    final thumbBytes = await Isolate.run(
      () => _generateThumbnailBytes(Uint8List.fromList(plainPhoto)),
    );
    final encryptedThumb = await _cryptoService.encrypt(
      thumbBytes,
      dek,
      aad: utf8.encode('${photo.id}:thumb:v${photo.encryptionVersion}'),
    );
    await _writePayloadFile(
      id: photo.id,
      kind: 'thumb',
      payload: encryptedThumb,
    );
    return thumbBytes;
  }

  Future<String> _writePayloadFile({
    required String id,
    required String kind,
    required EncryptedPayload payload,
  }) async {
    final vaultRoot = await _resolveVaultRoot();
    final folderName = kind == 'thumb' ? 'thumbs' : 'objects';
    final vaultDir = Directory(p.join(vaultRoot.path, folderName));
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
        p.join(split[0], 'Android', 'media', packageName, 'vault'),
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
    required String source,
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
    final photosMap =
        (doc['photos'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
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
      'source': source,
      'driveUploadRequested': _driveEncryptedBackupEnabled,
      'updatedAtMs': DateTime.now().millisecondsSinceEpoch,
    };
    doc['photos'] = photosMap;
    await manifestFile.writeAsString(jsonEncode(doc), flush: true);
  }

  Future<void> _removeManifestEntry(String id) async {
    if (!_useExternalStorageMirror) return;
    final root = await _resolveVaultRoot();
    final manifestFile = File(p.join(root.path, 'manifest', 'manifest.json'));
    if (!await manifestFile.exists()) return;
    try {
      final parsed = jsonDecode(await manifestFile.readAsString());
      if (parsed is! Map<String, dynamic>) return;
      final photosMap =
          (parsed['photos'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      photosMap.remove(id);
      parsed['photos'] = photosMap;
      await manifestFile.writeAsString(jsonEncode(parsed), flush: true);
    } catch (_) {}
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
}

Map<String, Object> _prepareImportFile(String filePath) {
  final file = File(filePath);
  final plainBytes = file.readAsBytesSync();
  if (plainBytes.isEmpty) {
    throw StateError('Selected file is empty.');
  }
  final originalFilename = p.basename(
    filePath.isEmpty ? 'imported.jpg' : filePath,
  );
  final mimeType = _mimeFromFileName(originalFilename);
  if (!_isSupportedMimeType(mimeType)) {
    throw UnsupportedError('Unsupported file type: $mimeType');
  }
  final thumbnailBytes = _generateThumbnailBytes(plainBytes);
  return <String, Object>{
    'originalFilename': originalFilename,
    'mimeType': mimeType,
    'fileSize': plainBytes.length,
    'checksumSha256': crypto.sha256.convert(plainBytes).toString(),
    'photoBytes': Uint8List.fromList(plainBytes),
    'thumbnailBytes': thumbnailBytes,
  };
}

Uint8List _generateThumbnailBytes(Uint8List plainBytes) {
  final decoded = img.decodeImage(plainBytes);
  if (decoded == null) {
    throw UnsupportedError('Unable to decode image.');
  }
  final normalized = img.bakeOrientation(decoded);
  final maxDimension = normalized.width >= normalized.height
      ? normalized.width
      : normalized.height;
  final resized = maxDimension <= 512
      ? normalized
      : img.copyResize(
          normalized,
          width: normalized.width >= normalized.height ? 512 : null,
          height: normalized.height > normalized.width ? 512 : null,
          interpolation: img.Interpolation.average,
        );
  return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
}

String _mimeFromFileName(String filename) {
  final lower = filename.toLowerCase();
  if (lower.endsWith('.png')) return 'image/png';
  if (lower.endsWith('.webp')) return 'image/webp';
  if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
  return 'image/jpeg';
}

bool _isSupportedMimeType(String mimeType) {
  return mimeType == 'image/jpeg' ||
      mimeType == 'image/png' ||
      mimeType == 'image/webp' ||
      mimeType == 'image/heic';
}
