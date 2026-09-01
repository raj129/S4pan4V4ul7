import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/entities/chat_user.dart';
import '../../domain/entities/wrapped_identity_key.dart';
import '../../domain/repositories/user_repository.dart';

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository({FirebaseFirestore? firestore})
    : _db =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'default1',
          );

  final FirebaseFirestore _db;

  /// Firestore caps `whereIn` at 30 values per query.
  static const _whereInLimit = 30;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');

  /// Owner-only document holding the wrapped identity key.
  DocumentReference<Map<String, dynamic>> _privateKeys(String uid) =>
      _users.doc(uid).collection('private').doc('keys');

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
  Future<void> updatePublicKey({
    required String uid,
    required String publicKeyBase64,
  }) async {
    await _users.doc(uid).update({'publicKey': publicKeyBase64});
  }

  @override
  Future<List<ChatUser>> getUsersByEmails(List<String> emails) async {
    final normalised = emails
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (normalised.isEmpty) return const [];

    final found = <String, ChatUser>{};
    for (var i = 0; i < normalised.length; i += _whereInLimit) {
      final chunk = normalised.skip(i).take(_whereInLimit).toList();
      final query = await _users.where('email', whereIn: chunk).get();
      for (final doc in query.docs) {
        final user = ChatUser.fromFirestore(doc.data());
        found[user.uid] = user;
      }
    }
    return found.values.toList();
  }

  @override
  Future<WrappedIdentityKey?> getWrappedIdentityKey(String uid) async {
    final doc = await _privateKeys(uid).get();
    return WrappedIdentityKey.fromFirestore(doc.data());
  }

  @override
  Future<void> saveWrappedIdentityKey({
    required String uid,
    required WrappedIdentityKey wrapped,
  }) async {
    await _privateKeys(uid).set(wrapped.toFirestore(), SetOptions(merge: true));
  }
}
