import 'dart:io';
import 'dart:typed_data';

/// A place named blobs can be kept (device folder, Google Drive).
///
/// Works on files, not byte arrays, so large photos are streamed. Names are
/// flat file names chosen by the caller. Stores never see plaintext: callers
/// only pass ciphertext or already-encrypted manifests.
abstract class BackupBlobStore {
  /// Short label for UI and logs, e.g. "This device" or "Google Drive".
  String get label;

  /// Whether a network connection is needed.
  bool get requiresNetwork;

  /// Cloud stores are gated by the "Back up to Google Drive" setting.
  bool get isCloud;

  /// Copies [source] into the store under [name], replacing any existing blob.
  Future<void> writeFile(String name, File source, {bool interactive = false});

  /// Streams the blob [name] into [destination]. Returns false if it does not
  /// exist; [destination] is only written when the blob exists.
  Future<bool> readToFile(
    String name,
    File destination, {
    bool interactive = false,
  });

  /// Names of all blobs that start with [prefix].
  Future<List<String>> list(String prefix, {bool interactive = false});

  /// Removes the blob named [name]; a missing blob is not an error.
  Future<void> delete(String name, {bool interactive = false});
}

/// Extension of [BackupBlobStore] for small in-memory payloads (chat snapshots,
/// wrapped VMK JSON) so all backup artifacts share identical local recovery
/// folders, atomic writes, and Google Drive appDataFolder handling.
abstract class BackupByteStore extends BackupBlobStore {
  /// Writes [bytes] atomically under [name], replacing any existing blob.
  Future<void> writeBytes(
    String name,
    Uint8List bytes, {
    bool interactive = false,
  });

  /// Reads the blob [name] into memory, or returns null if it does not exist.
  Future<Uint8List?> readBytes(String name, {bool interactive = false});
}
