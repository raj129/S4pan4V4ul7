import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';

/// Stores the caller's profile photo where their contacts can read it.
abstract class AvatarStorage {
  /// Uploads [jpegBytes] and returns an https download URL.
  Future<String> upload(String uid, Uint8List jpegBytes);

  /// Best-effort removal of the caller's uploaded photo.
  Future<void> delete(String uid);
}

class FirebaseAvatarStorage implements AvatarStorage {
  FirebaseAvatarStorage({FirebaseStorage? storage}) : _storage = storage;

  FirebaseStorage? _storage;

  Reference _ref(String uid) =>
      (_storage ??= FirebaseStorage.instance).ref('profiles/$uid/avatar.jpg');

  @override
  Future<String> upload(String uid, Uint8List jpegBytes) async {
    final ref = _ref(uid);
    await ref.putData(jpegBytes, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();
    // The path is constant, so a version query keeps image caches from
    // serving the previous photo.
    return '$url&v=${DateTime.now().millisecondsSinceEpoch}';
  }

  @override
  Future<void> delete(String uid) async {
    try {
      await _ref(uid).delete();
    } catch (_) {}
  }
}
