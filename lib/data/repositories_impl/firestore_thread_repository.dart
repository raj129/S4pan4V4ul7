import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/chat_thread.dart';
import '../../domain/repositories/thread_repository.dart';

class FirestoreThreadRepository implements ThreadRepository {
  FirestoreThreadRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _threads =>
      _db.collection('threads');

  DocumentReference<Map<String, dynamic>> _typingDoc(String threadId) =>
      _threads.doc(threadId).collection('meta').doc('typing');

  @override
  Future<ChatThread> createOrGetThread({
    required String myUid,
    required String otherUid,
  }) async {
    final threadId = ChatThread.buildId(myUid, otherUid);
    final ref = _threads.doc(threadId);
    final snap = await ref.get();
    if (snap.exists && snap.data() != null) {
      return ChatThread.fromFirestore(snap.data()!);
    }
    final now = DateTime.now().toUtc();
    final thread = ChatThread(
      threadId: threadId,
      participantIds: [myUid, otherUid],
      lastMessage: '',
      lastMessageAt: now,
      unreadCounts: {myUid: 0, otherUid: 0},
      createdAt: now,
    );
    await ref.set(thread.toFirestore());
    return thread;
  }

  @override
  Stream<List<ChatThread>> watchThreadsForUser(String uid) {
    return _threads
        .where('participantIds', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatThread.fromFirestore(d.data())).toList());
  }

  @override
  Future<ChatThread?> getThread(String threadId) async {
    final snap = await _threads.doc(threadId).get();
    if (!snap.exists || snap.data() == null) return null;
    return ChatThread.fromFirestore(snap.data()!);
  }

  @override
  Future<void> updateLastMessage({
    required String threadId,
    required String preview,
    required DateTime sentAt,
  }) async {
    await _threads.doc(threadId).update({
      'lastMessage': preview,
      'lastMessageAt': sentAt.toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> incrementUnread({
    required String threadId,
    required String recipientUid,
  }) async {
    await _threads.doc(threadId).update({
      'unreadCounts.$recipientUid': FieldValue.increment(1),
    });
  }

  @override
  Future<void> resetUnread({
    required String threadId,
    required String uid,
  }) async {
    await _threads.doc(threadId).update({'unreadCounts.$uid': 0});
  }

  @override
  Future<void> deleteThread(String threadId) async {
    // Firestore does not recursively delete subcollections from the client.
    // The messages subcollection must be cleared separately via MessageRepository.
    await _threads.doc(threadId).delete();
  }

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
