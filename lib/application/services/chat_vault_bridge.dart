import 'dart:io';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/entities/vault_photo.dart';
import '../../domain/repositories/photo_repository.dart';
import '../usecases/export_photo_usecase.dart';
import 'import_manager.dart';

/// Moves media between the encrypted vault and the encrypted chat.
///
/// Both stores already encrypt at rest, but with different keys, so every
/// transfer is a decrypt-then-re-encrypt. Plaintext only ever exists in memory
/// or in a private temp file that is deleted immediately afterwards — it is
/// never written to shared storage.
class ChatVaultBridge {
  ChatVaultBridge({
    required PhotoRepository photoRepository,
    required ExportPhotoUseCase exportPhoto,
    required ImportManager importManager,
  }) : _photoRepository = photoRepository,
       _exportPhoto = exportPhoto,
       _importManager = importManager;

  final PhotoRepository _photoRepository;
  final ExportPhotoUseCase _exportPhoto;
  final ImportManager _importManager;

  /// A page of vault photos to choose from when attaching.
  Future<List<VaultPhoto>> listVaultPhotos({
    int page = 0,
    int pageSize = 60,
  }) {
    return _photoRepository.listGalleryPage(page: page, pageSize: pageSize);
  }

  /// Decrypt a vault photo so it can be re-encrypted for a chat thread.
  Future<Uint8List> readVaultPhoto(VaultPhoto photo) async {
    final bytes = await _exportPhoto.decryptToBytes(photo);
    return Uint8List.fromList(bytes);
  }

  /// Thumbnail for the attachment picker.
  Future<Uint8List?> thumbnailOf(VaultPhoto photo) =>
      _importManager.loadThumbnailBytes(photo);

  /// Import received chat media into the vault.
  ///
  /// [ImportManager] works from files, so the decrypted bytes are staged in the
  /// app's private temp directory. The staged copy is removed as soon as the
  /// import finishes, leaving only the vault's own encrypted copy.
  Future<void> saveToVault({
    required Uint8List bytes,
    required String filename,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final stagingDir = Directory(p.join(tempDir.path, 'chat_to_vault'));
    if (!await stagingDir.exists()) {
      await stagingDir.create(recursive: true);
    }
    final staged = File(p.join(stagingDir.path, filename));
    await staged.writeAsBytes(bytes, flush: true);
    try {
      await _importManager.enqueueImport(
        files: [XFile(staged.path)],
        source: 'chat',
      );
    } finally {
      try {
        if (await staged.exists()) await staged.delete();
      } catch (_) {
        // Best-effort: a leftover temp file is cleared with the app cache.
      }
    }
  }
}
