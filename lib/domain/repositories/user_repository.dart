import '../entities/chat_user.dart';

abstract class UserRepository {
  /// Create or update the current user's Firestore profile.
  Future<void> upsertProfile(ChatUser user);

  /// Fetch a user by their UID.
  Future<ChatUser?> getUserById(String uid);

  /// Look up a user by exact Gmail address.
  /// Returns null if not registered.
  Future<ChatUser?> getUserByEmail(String email);

  /// Stream the current user's profile (for live updates).
  Stream<ChatUser?> watchUser(String uid);

  /// Update only online status and last-seen timestamp.
  Future<void> updatePresence({
    required String uid,
    required bool isOnline,
    required DateTime lastSeen,
  });

  /// Store the user's ECDH public key in Firestore.
  Future<void> updatePublicKey({
    required String uid,
    required String publicKeyBase64,
  });
}
