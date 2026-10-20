import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../features/vault/domain/entities/vault_photo.dart';
import '../../features/vault/application/services/import_manager.dart';

typedef ChatMoveCallback = Future<void> Function();

class ChatVaultMoveResult {
  const ChatVaultMoveResult({
    required this.item,
    required this.deduplicated,
    required this.cleanupPending,
    this.cleanupError,
  });

  final VaultPhoto item;
  final bool deduplicated;
  final bool cleanupPending;
  final Object? cleanupError;
}

/// Cross-feature adapter for manual chat-to-vault imports. It neither
/// downloads nor auto-imports media.
/// Callers authenticate received ciphertext before providing these bytes and
/// pin the source until completion. Callback operations must be idempotent and
/// check account ownership: process death can repeat either one.
class ChatAttachmentVaultImporter {
  ChatAttachmentVaultImporter(this._manager);
  final ImportManager _manager;
  static const maxAttachmentBytes = 64 * 1024 * 1024 - 1024;

  Future<ChatVaultMoveResult> move({
    required Uint8List bytes,
    required String filename,
    required String sourceId,
    String? mediaType,
    String? mimeType,
    ChatMoveCallback? onMarkMoved,
    ChatMoveCallback? onSourceCleanup,
  }) => _manager.runChatImport(() async {
    _validateSource(sourceId);
    _manager.requireChatImportUnlock();
    final safeName = validateFilename(filename);
    if (bytes.isEmpty || bytes.length > maxAttachmentBytes) {
      throw ArgumentError('Attachment must be nonempty and below 64 MB.');
    }
    final checksum = sha256.convert(bytes).toString();
    final old = await _manager.readChatMove(sourceId);
    if (old != null && old['checksum'] != checksum) {
      throw StateError(
        'Move source identity already belongs to other content.',
      );
    }
    var journal = old;
    VaultPhoto? item;
    var duplicate = old?['deduplicated'] == true;
    if (journal != null) {
      item = await _manager.chatImportById(journal['id'] as String);
      if (item == null && journal['phase'] != 'importing') {
        throw StateError(
          'Previously committed vault attachment is unavailable.',
        );
      }
    }
    if (item == null) {
      final prepared = prepareAttachment(
        bytes,
        mediaType: mediaType,
        mimeType: mimeType,
      );
      try {
        item = await _manager.findChatImportDuplicate(checksum);
        duplicate = item != null;
        final id = item?.id ?? journal?['id'] as String? ?? const Uuid().v4();
        journal = {
          'id': id,
          'checksum': checksum,
          'phase': 'importing',
          'deduplicated': duplicate,
        };
        // Persist the intended ID before files or repository writes. A restart
        // reconciles this ID after an ambiguous database commit.
        await _manager.writeChatMove(sourceId, journal);
        item ??= await _manager.commitChatAttachment(
          id: id,
          bytes: bytes,
          thumbnail: prepared.thumbnail,
          filename: safeName,
          mimeType: prepared.mimeType,
          checksum: checksum,
        );
      } finally {
        prepared.thumbnail.fillRange(0, prepared.thumbnail.length, 0);
      }
    }
    await _manager.verifyChatVaultItem(item, checksum);
    journal = {
      'id': item.id,
      'checksum': checksum,
      'phase': 'committed',
      'deduplicated': duplicate,
    };
    // No cleanup may run before this durable commit checkpoint.
    await _manager.writeChatMove(sourceId, journal);
    return _cleanup(sourceId, item, journal, onMarkMoved, onSourceCleanup);
  });

  /// Resume a committed intent using only the account/thread/ref identity.
  /// An interrupted pre-commit import still needs authenticated source bytes.
  Future<ChatVaultMoveResult?> resume({
    required String sourceId,
    ChatMoveCallback? onMarkMoved,
    ChatMoveCallback? onSourceCleanup,
  }) => _manager.runChatImport(() async {
    _validateSource(sourceId);
    _manager.requireChatImportUnlock();
    final journal = await _manager.readChatMove(sourceId);
    if (journal == null) return null;
    final item = await _manager.chatImportById(journal['id'] as String);
    if (item == null) {
      if (journal['phase'] == 'importing') return null;
      throw StateError('Committed vault attachment is unavailable.');
    }
    await _manager.verifyChatVaultItem(item, journal['checksum'] as String);
    journal['phase'] = 'committed';
    await _manager.writeChatMove(sourceId, journal);
    return _cleanup(sourceId, item, journal, onMarkMoved, onSourceCleanup);
  });

  Future<ChatVaultMoveResult> _cleanup(
    String sourceId,
    VaultPhoto item,
    Map<String, dynamic> journal,
    ChatMoveCallback? mark,
    ChatMoveCallback? cleanup,
  ) async {
    Object? error;
    var pending = true;
    try {
      if (mark != null && cleanup != null) {
        _manager.requireChatImportUnlock();
        // Suppress background re-download before removing the cached object.
        await mark();
        journal['phase'] = 'marked';
        await _manager.writeChatMove(sourceId, journal);
        await cleanup();
        journal['phase'] = 'complete';
        await _manager.writeChatMove(sourceId, journal);
        pending = false;
      }
    } catch (e) {
      error = e;
    }
    return ChatVaultMoveResult(
      item: item,
      deduplicated: journal['deduplicated'] == true,
      cleanupPending: pending,
      cleanupError: error,
    );
  }

  static void _validateSource(String sourceId) {
    if (sourceId.isEmpty || utf8.encode(sourceId).length > 8192) {
      throw ArgumentError('A stable account/thread/ref source ID is required.');
    }
  }

  static String validateFilename(String name) {
    if (name.isEmpty ||
        name.trim().isEmpty ||
        name.length > 255 ||
        name == '.' ||
        name == '..' ||
        name.contains(RegExp(r'[/\\:\x00-\x1f\x7f]'))) {
      throw ArgumentError('Unsafe attachment filename.');
    }
    return name;
  }

  static PreparedChatAttachment prepareAttachment(
    Uint8List bytes, {
    String? mediaType,
    String? mimeType,
  }) {
    bool prefix(List<int> magic) =>
        bytes.length >= magic.length &&
        List.generate(magic.length, (i) => bytes[i]).join(',') ==
            magic.join(',');
    String ascii(int start, int end) => bytes.length >= end
        ? String.fromCharCodes(bytes.sublist(start, end))
        : '';
    String detected = 'application/octet-stream';
    if (prefix([0xff, 0xd8, 0xff])) detected = 'image/jpeg';
    if (prefix([137, 80, 78, 71, 13, 10, 26, 10])) detected = 'image/png';
    if (ascii(0, 3) == 'GIF') detected = 'image/gif';
    if (ascii(0, 4) == 'RIFF' && ascii(8, 12) == 'WEBP') {
      detected = 'image/webp';
    }
    if (ascii(0, 5) == '%PDF-') detected = 'application/pdf';
    if (ascii(4, 8) == 'ftyp') {
      final brand = ascii(8, 12);
      detected = brand == 'M4A ' ? 'audio/mp4' : 'video/mp4';
      if (['heic', 'heix', 'heif', 'mif1', 'avif'].contains(brand)) {
        // HEIF/AVIF cannot be decoded by the vault photo pipeline. Keep the
        // original bytes usable as generic attachments instead.
        detected = 'application/octet-stream';
      }
    }
    if (ascii(0, 3) == 'ID3' ||
        (bytes.length > 1 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0)) {
      if (!detected.startsWith('image/')) detected = 'audio/mpeg';
    }
    if (ascii(0, 4) == 'RIFF' && ascii(8, 12) == 'WAVE') detected = 'audio/wav';
    if (ascii(0, 4) == 'OggS') detected = 'audio/ogg';
    if (ascii(0, 4) == 'fLaC') detected = 'audio/flac';
    if (prefix([0x1a, 0x45, 0xdf, 0xa3])) detected = 'video/webm';
    if (detected.startsWith('image/')) {
      img.Image? image;
      try {
        final decoder = img.findDecoderForData(bytes);
        final info = decoder?.startDecode(bytes);
        if (info == null ||
            info.width <= 0 ||
            info.height <= 0 ||
            info.width * info.height > 32 * 1024 * 1024) {
          throw const FormatException(
            'Received image dimensions exceed the preview budget.',
          );
        }
        image = decoder?.decodeFrame(0);
      } catch (_) {
        throw const FormatException('Corrupt received image.');
      }
      if (image == null) throw FormatException('Corrupt received image.');
      final normalized = img.bakeOrientation(image);
      final resized = img.copyResize(
        normalized,
        width: normalized.width >= normalized.height ? 512 : null,
        height: normalized.height > normalized.width ? 512 : null,
      );
      return PreparedChatAttachment(
        detected,
        Uint8List.fromList(img.encodeJpg(resized, quality: 82)),
      );
    }
    if (detected == 'application/octet-stream' &&
        (mediaType == 'image' || mimeType?.startsWith('image/') == true) &&
        ascii(4, 8) != 'ftyp') {
      throw FormatException('Received image signature is invalid.');
    }
    // Never send video/audio/documents to an image decoder. The encrypted
    // neutral icon remains compatible with existing vault thumbnail storage.
    final icon = img.Image(width: 64, height: 64);
    img.fill(icon, color: img.ColorRgb8(65, 78, 96));
    return PreparedChatAttachment(
      detected,
      Uint8List.fromList(img.encodeJpg(icon)),
    );
  }
}

class PreparedChatAttachment {
  const PreparedChatAttachment(this.mimeType, this.thumbnail);
  final String mimeType;
  final Uint8List thumbnail;
}
