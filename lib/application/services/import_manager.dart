import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/entities/vault_photo.dart';
import '../../domain/repositories/photo_repository.dart';

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
  ImportManager({required PhotoRepository photoRepository})
    : _photoRepository = photoRepository;

  final PhotoRepository _photoRepository;
  static const _uuid = Uuid();
  final List<XFile> _pendingShareFiles = [];
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
      for (final file in files) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final now = DateTime.now().millisecondsSinceEpoch;
        final name = p.basename(file.path.isEmpty ? 'imported.jpg' : file.path);
        final fileSize = await file.length();
        final id = _uuid.v4();
        final random = Random.secure();
        final nonce = List<int>.generate(12, (_) => random.nextInt(256))
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();

        await _photoRepository.upsertPhoto(
          VaultPhoto(
            id: id,
            originalFilename: name,
            encryptedFilePath: file.path,
            thumbnailPath: file.path,
            wrappedDek: 'pending-wrap-$id',
            photoNonce: nonce,
            thumbnailNonce: nonce,
            encryptionVersion: 1,
            checksumSha256: 'pending-checksum-$id',
            fileSize: fileSize,
            mimeType: _mimeFromFileName(name),
            createdTimeMs: now,
            importedTimeMs: now,
            modifiedTimeMs: now,
            favorite: false,
            isTrashed: false,
          ),
        );

        completed += 1;
        _progress = ImportJobProgress(
          jobId: jobId,
          total: files.length,
          completed: completed,
          status: ImportJobStatus.running,
        );
        notifyListeners();
      }

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

  String _mimeFromFileName(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }
}
