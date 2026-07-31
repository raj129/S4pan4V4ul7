import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/message_repository.dart';

class FirestoreMessageRepository implements MessageRepository {
  FirestoreMessageRepository({
    FirebaseFirestore? firestore,
  }) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> _messages(String threadId) =>
      _db.collection('threads').doc(threadId).collection('messages');

  @override
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String senderId,
    required String encryptedText,
    String? mediaRef,
    MessageType? mediaType,
  }) async {
    final msgId = _uuid.v4();
    final now = DateTime.now().toUtc();
    final msg = ChatMessage(
      messageId: msgId,
      threadId: threadId,
      senderId: senderId,
      encryptedText: encryptedText,
      sentAt: now,
      deletedFor: const [],
      mediaRef: mediaRef,
      mediaType: mediaType,
    );
    await _messages(threadId).doc(msgId).set(msg.toFirestore());
    return msg;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId) {
    return _messages(threadId)
        .orderBy('sentAt', descending: true)
        .limit(30)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromFirestore(d.data())).toList());
  }

  @override
  Future<List<ChatMessage>> loadBefore({
    required String threadId,
    required DateTime before,
    int limit = 30,
  }) async {
    final snap = await _messages(threadId)
        .where('sentAt', isLessThan: before.toUtc().millisecondsSinceEpoch)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs.map((d) => ChatMessage.fromFirestore(d.data())).toList();
  }

  @override
  Future<void> deleteMessageForUser({
    required String threadId,
    required String messageId,
    required String uid,
  }) async {
    await _messages(threadId).doc(messageId).update({
      'deletedFor': FieldValue.arrayUnion([uid]),
    });
  }

  @override
  Future<void> deleteMessageForEveryone({
    required String threadId,
    required String messageId,
  }) async {
    await _messages(threadId).doc(messageId).delete();
  }

  @override
  Future<void> deleteAllMessages(String threadId) async {
    const batchSize = 100;
    while (true) {
      final snap = await _messages(threadId).limit(batchSize).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }
  }
}

class FirebaseMediaRepository implements MediaRepository {
  FirebaseMediaRepository({FirebaseStorage? storage})
      : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  Reference _ref(String threadId, String messageId, String filename) =>
      _storage.ref('chat_media/$threadId/$messageId/$filename');

  @override
  Future<String> uploadEncryptedMedia({
    required String threadId,
    required String messageId,
    required String filename,
    required Uint8List encryptedBytes,
  }) async {
    final ref = _ref(threadId, messageId, filename);
    await ref.putData(
      encryptedBytes,
      SettableMetadata(contentType: 'application/octet-stream'),
    );
    return ref.fullPath;
  }

  @override
  Future<Uint8List> downloadEncryptedMedia(String storagePath) async {
    final data = await _storage.ref(storagePath).getData();
    return data ?? Uint8List(0);
  }

  @override
  Future<void> deleteMedia(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }

  @override
  Future<void> deleteThreadMedia(String threadId) async {
    try {
      final listResult = await _storage.ref('chat_media/$threadId').listAll();
      for (final prefix in listResult.prefixes) {
        final inner = await prefix.listAll();
        for (final item in inner.items) {
          await item.delete();
        }
      }
    } on FirebaseException catch (e) {
      if (e.code != 'object-not-found') rethrow;
    }
  }
}
