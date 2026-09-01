import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_metadata.dart';
import '../../domain/entities/message_reply.dart';
import '../../domain/repositories/message_repository.dart';

class FirestoreMessageRepository implements MessageRepository {
  FirestoreMessageRepository({FirebaseFirestore? firestore})
    : _db =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'default1',
          );

  final FirebaseFirestore _db;
  final _uuid = const Uuid();

  /// Firestore rejects batches larger than 500 writes.
  static const _maxBatchSize = 400;

  CollectionReference<Map<String, dynamic>> _messages(String threadId) =>
      _db.collection('threads').doc(threadId).collection('messages');

  @override
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String senderId,
    required String encryptedText,
    String? messageId,
    String? mediaRef,
    MessageType? mediaType,
    MediaMeta? mediaMeta,
    MessageReply? replyTo,
    bool isForwarded = false,
  }) async {
    final msgId = messageId ?? _uuid.v4();
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
      mediaMeta: mediaMeta,
      replyTo: replyTo,
      isForwarded: isForwarded,
      status: MessageStatus.sent,
    );
    await _messages(threadId).doc(msgId).set(msg.toFirestore());
    return msg;
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId, {int limit = 30}) {
    return _messages(threadId)
        .orderBy('sentAt', descending: true)
        .limit(limit)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => ChatMessage.fromFirestore(d.data()))
              .toList(),
        );
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
  Future<ChatMessage?> getMessage({
    required String threadId,
    required String messageId,
  }) async {
    final doc = await _messages(threadId).doc(messageId).get();
    final data = doc.data();
    if (data == null) return null;
    return ChatMessage.fromFirestore(data);
  }

  @override
  Future<void> editMessage({
    required String threadId,
    required String messageId,
    required String encryptedText,
  }) async {
    await _messages(threadId).doc(messageId).update({
      'encryptedText': encryptedText,
      'editedAt': DateTime.now().toUtc().millisecondsSinceEpoch,
    });
  }

  @override
  Future<void> setReaction({
    required String threadId,
    required String messageId,
    required String uid,
    required String? emoji,
  }) async {
    // Dotted field paths would break on UIDs containing '.', so address the
    // nested key explicitly.
    final field = FieldPath(['reactions', uid]);
    await _messages(threadId).doc(messageId).update({
      field: emoji ?? FieldValue.delete(),
    });
  }

  @override
  Future<void> markRead({
    required String threadId,
    required List<String> messageIds,
    required String uid,
  }) async {
    if (messageIds.isEmpty) return;
    for (var i = 0; i < messageIds.length; i += _maxBatchSize) {
      final chunk = messageIds.skip(i).take(_maxBatchSize);
      final batch = _db.batch();
      for (final id in chunk) {
        batch.update(_messages(threadId).doc(id), {
          'readBy': FieldValue.arrayUnion([uid]),
        });
      }
      await batch.commit();
    }
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
    // Keep the document as a tombstone and strip every payload field, so both
    // sides render "This message was deleted" and no ciphertext is retained.
    await _messages(threadId).doc(messageId).update({
      'deletedForEveryone': true,
      'encryptedText': '',
      'reactions': <String, String>{},
      'mediaRef': FieldValue.delete(),
      'mediaType': FieldValue.delete(),
      'mediaMeta': FieldValue.delete(),
      'encryptedMediaKey': FieldValue.delete(),
      'replyTo': FieldValue.delete(),
    });
  }

  @override
  Future<void> deleteAllMessages(String threadId) async {
    while (true) {
      final snap = await _messages(threadId).limit(_maxBatchSize).get();
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

  /// Upper bound for a single download, guarding against a malicious or
  /// corrupt object exhausting device memory.
  static const _maxDownloadBytes = 64 * 1024 * 1024;

  Reference _ref(String threadId, String messageId, String filename) =>
      _storage.ref('chat_media/$threadId/$messageId/$filename');

  @override
  Future<String> uploadEncryptedMedia({
    required String threadId,
    required String messageId,
    required String filename,
    required Uint8List encryptedBytes,
    void Function(double progress)? onProgress,
  }) async {
    final ref = _ref(threadId, messageId, filename);
    final task = ref.putData(
      encryptedBytes,
      SettableMetadata(contentType: 'application/octet-stream'),
    );
    if (onProgress != null) {
      task.snapshotEvents.listen(
        (snapshot) {
          if (snapshot.totalBytes > 0) {
            onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
          }
        },
        // Failures surface from awaiting the task itself.
        onError: (_) {},
      );
    }
    await task;
    return ref.fullPath;
  }

  @override
  Future<Uint8List> downloadEncryptedMedia(String storagePath) async {
    final data = await _storage.ref(storagePath).getData(_maxDownloadBytes);
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
