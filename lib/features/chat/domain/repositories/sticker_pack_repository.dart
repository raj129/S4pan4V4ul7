import 'dart:typed_data';

import '../entities/local_sticker.dart';

/// The user's personal, device-local sticker pack.
///
/// Presentation depends on this abstraction rather than the encrypted file
/// implementation, so the storage can change (or be faked in tests) without
/// touching widgets.
abstract interface class StickerPackRepository {
  /// Largest single sticker accepted by [addSticker].
  static const maxStickerBytes = 4 * 1024 * 1024;

  /// Newest first.
  Future<List<LocalSticker>> list();

  Future<Uint8List> readBytes(LocalSticker sticker);

  /// Adds a sticker, returning the existing one if identical bytes are
  /// already saved. Throws [StateError] when the pack is full.
  Future<LocalSticker> addSticker({
    required List<int> bytes,
    required String extension,
    String label = '',
  });

  Future<void> remove(LocalSticker sticker);
}
