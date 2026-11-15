import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show Listenable;

import '../../features/vault/domain/entities/vault_photo.dart';
import '../../features/vault/domain/repositories/photo_repository.dart';
import '../../features/vault/application/usecases/export_photo_usecase.dart';
import '../../features/vault/application/services/import_manager.dart';
import 'chat_attachment_vault_importer.dart';

export 'chat_attachment_vault_importer.dart'
    show ChatVaultMoveResult, ChatMoveCallback;

/// Links chat attachments to encrypted Vault objects.
///
/// The chat message/cloud object remains intact. Its local encrypted cache is
/// removed after import, and the chat views read the linked Vault object.
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
  late final _attachmentImporter = ChatAttachmentVaultImporter(_importManager);
  Listenable get vaultSessionChanges => _importManager.chatVaultSessionChanges;
  bool get isUnlocked => _importManager.isChatVaultUnlocked;

  /// A page of vault photos to choose from when attaching.
  Future<List<VaultPhoto>> listVaultPhotos({int page = 0, int pageSize = 60}) {
    return _photoRepository.listGalleryPage(page: page, pageSize: pageSize);
  }

  /// Decrypt a vault photo so it can be re-encrypted for a chat thread.
  Future<Uint8List> readVaultPhoto(VaultPhoto photo) async {
    final bytes = await _exportPhoto.decryptToBytes(photo);
    try {
      return Uint8List.fromList(bytes);
    } finally {
      try {
        bytes.fillRange(0, bytes.length, 0);
      } catch (_) {
        // Managed/cryptography buffers cannot always be erased.
      }
    }
  }

  /// Thumbnail for the attachment picker.
  Future<Uint8List?> thumbnailOf(VaultPhoto photo) =>
      _importManager.loadThumbnailBytes(photo);

  /// Save an attachment as a local Vault item linked to its chat source.
  Future<ChatVaultMoveResult> moveToVault({
    required Uint8List bytes,
    required String filename,
    required String sourceId,
    String? mediaType,
    String? mimeType,
    ChatMoveCallback? onMarkMoved,
    ChatMoveCallback? onSourceCleanup,
  }) => _attachmentImporter.move(
    bytes: bytes,
    filename: filename,
    sourceId: sourceId,
    mediaType: mediaType,
    mimeType: mimeType,
    onMarkMoved: onMarkMoved,
    onSourceCleanup: onSourceCleanup,
  );

  Future<ChatVaultMoveResult?> resumeMove({
    required String sourceId,
    ChatMoveCallback? onMarkMoved,
    ChatMoveCallback? onSourceCleanup,
  }) => _attachmentImporter.resume(
    sourceId: sourceId,
    onMarkMoved: onMarkMoved,
    onSourceCleanup: onSourceCleanup,
  );

  Future<VaultPhoto?> linkedAttachment(String sourceId) {
    if (!isUnlocked) return Future<VaultPhoto?>.value();
    return _importManager.linkedChatAttachment(sourceId);
  }

  Future<Uint8List?> loadLinkedAttachment(String sourceId) async {
    final photo = await linkedAttachment(sourceId);
    if (photo == null) return null;
    return _importManager.loadPhotoBytes(photo);
  }

  Future<Uint8List?> loadLinkedThumbnail(String sourceId) async {
    final photo = await linkedAttachment(sourceId);
    if (photo == null) return null;
    final bytes = await _importManager.loadThumbnailBytes(photo);
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  Future<List<String>> linkedAttachmentSources(String photoId) =>
      _importManager.chatAttachmentLinkSources(photoId);

  Future<void> moveAttachmentToTrash(
    VaultPhoto photo, {
    required int expiresAtMs,
  }) => _photoRepository.movePhotoToTrash(photo.id, expiresAtMs: expiresAtMs);

  Future<void> restoreAttachmentFromTrash(String photoId) =>
      _photoRepository.restoreFromTrash(photoId);

  Future<void> unlinkAttachment(String sourceId) =>
      _importManager.removeChatAttachmentLink(sourceId);

  Future<List<VaultPhoto>> listSavedAttachments() =>
      _importManager.listChatVaultAttachments();

  /// Compatibility entrypoint; callers that need source cleanup must use
  /// [moveToVault] with an account/thread/ref-scoped identity.
  Future<ChatVaultMoveResult> saveToVault({
    required Uint8List bytes,
    required String filename,
  }) => moveToVault(
    bytes: bytes,
    filename: filename,
    sourceId: 'legacy-manual:${sha256.convert(bytes)}',
  );
}
