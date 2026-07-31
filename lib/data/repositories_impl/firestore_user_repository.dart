import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/chat_user.dart';
import '../../domain/repositories/user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users => _db.collection('users');

  @override
  Future<void> upsertProfile(ChatUser user) async {
    await _users.doc(user.uid).set(user.toFirestore(), SetOptions(merge: true));
  }

  @override
  Future<ChatUser?> getUserById(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return ChatUser.fromFirestore(doc.data()!);
  }

  @override
  Future<ChatUser?> getUserByEmail(String email) async {
    final query = await _users
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();
    if (query.docs.isEmpty) return null;
    return ChatUser.fromFirestore(query.docs.first.data());
  }

  @override
  Stream<ChatUser?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return ChatUser.fromFirestore(snap.data()!);
    });
  }

  @override
  Future<void> updatePresence({
    required String uid,
    required bool isOnline,
    required DateTime lastSeen,
  }) async {
    await _users.doc(uid).update({
      'isOnline': isOnline,
      'lastSeen': lastSeen.toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> updatePublicKey({
    required String uid,
    required String publicKeyBase64,
  }) async {
    await _users.doc(uid).update({'publicKey': publicKeyBase64});
  }
}
