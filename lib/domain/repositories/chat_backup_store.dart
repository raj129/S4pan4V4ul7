import 'dart:typed_data';

/// A place an encrypted chat backup blob can be kept (device file, Drive).
///
/// Stores never see plaintext: the blob is encrypted before it arrives.
abstract class ChatBackupStore {
  /// Short label for UI and logs, e.g. "This device" or "Google Drive".
  String get label;

  /// Whether this store needs a network connection.
  bool get requiresNetwork;

  /// [interactive] allows prompting the user (e.g. to grant Drive access).
  Future<void> write(String accountId, Uint8List blob, {bool interactive = false});

  /// The stored blob for [accountId], or null if none exists.
  Future<Uint8List?> read(String accountId, {bool interactive = false});
}
