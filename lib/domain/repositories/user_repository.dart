import '../entities/chat_user.dart';
import '../entities/wrapped_identity_key.dart';

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

  /// Store the user's ECDH public key in Firestore.
  Future<void> updatePublicKey({
    required String uid,
    required String publicKeyBase64,
  });

  /// Look up several users by email in one round trip.
  ///
  /// Used by contact matching, where a device address book can produce
  /// hundreds of candidate addresses. Emails with no registered user are
  /// simply absent from the result.
  Future<List<ChatUser>> getUsersByEmails(List<String> emails);

  /// Read the caller's own wrapped identity key.
  ///
  /// Lives in the private `users/{uid}/private/keys` document, which security
  /// rules restrict to its owner — it must never be readable by other users,
  /// since a PIN is brute-forceable given the blob.
  Future<WrappedIdentityKey?> getWrappedIdentityKey(String uid);

  /// Persist the caller's wrapped identity key.
  Future<void> saveWrappedIdentityKey({
    required String uid,
    required WrappedIdentityKey wrapped,
  });
}
