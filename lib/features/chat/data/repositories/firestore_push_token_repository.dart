import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/repositories/push_token_repository.dart';

/// Keeps one document per device at `users/{uid}/private/devices/tokens/{token}`.
///
/// The token doubles as the document ID so re-registering the same device is
/// idempotent. The path sits under `private/**`, which the security rules
/// restrict to the owner.
class FirestorePushTokenRepository implements PushTokenRepository {
  FirestorePushTokenRepository({FirebaseFirestore? firestore})
    : _db =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'default1',
          );

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid, String token) => _db
      .collection('users')
      .doc(uid)
      .collection('private')
      .doc('devices')
      .collection('tokens')
      .doc(token);

  @override
  Future<void> saveToken({required String uid, required String token}) =>
      _doc(uid, token).set({
        'token': token,
        'platform': 'android',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteToken({required String uid, required String token}) =>
      _doc(uid, token).delete();
}
