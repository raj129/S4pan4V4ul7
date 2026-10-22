/// Stores this device's FCM registration token so the server can push to it.
///
/// Tokens live under the owner's private subcollection: they are readable only
/// by that user (and by the Cloud Function via the Admin SDK), never by peers.
abstract class PushTokenRepository {
  Future<void> saveToken({required String uid, required String token});

  Future<void> deleteToken({required String uid, required String token});
}
