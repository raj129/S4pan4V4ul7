import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/repositories/typing_repository.dart';

class FirestoreTypingRepository implements TypingRepository {
  FirestoreTypingRepository({FirebaseFirestore? firestore})
    : _db =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'default1',
          );

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _typingDoc(String threadId) =>
      _db.collection('threads').doc(threadId).collection('meta').doc('typing');

  @override
  Future<void> setTyping({
    required String threadId,
    required String uid,
    required bool isTyping,
  }) async {
    await _typingDoc(threadId).set({uid: isTyping}, SetOptions(merge: true));
  }

  @override
  Stream<bool> watchTyping({
    required String threadId,
    required String otherUid,
  }) {
    return _typingDoc(threadId).snapshots().map((snap) {
      if (!snap.exists || snap.data() == null) return false;
      return (snap.data()![otherUid] as bool?) ?? false;
    });
  }
}
