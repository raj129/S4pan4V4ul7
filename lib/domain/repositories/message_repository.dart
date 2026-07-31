import 'dart:typed_data';

import '../entities/chat_message.dart';

abstract class MessageRepository {
  /// Send a message. Encryption must happen before calling this method.
  Future<ChatMessage> sendMessage({
    required String threadId,
    required String senderId,
    required String encryptedText,
    String? mediaRef,
    MessageType? mediaType,
  });

  /// Stream messages for a thread, newest first.
  Stream<List<ChatMessage>> watchMessages(String threadId);

  /// Load older messages before a cursor timestamp (pagination).
  Future<List<ChatMessage>> loadBefore({
    required String threadId,
    required DateTime before,
    int limit = 30,
  });

  /// Delete a message for the given user (appends uid to deletedFor).
  Future<void> deleteMessageForUser({
    required String threadId,
    required String messageId,
    required String uid,
  });

  /// Delete a message for everyone (removes the document entirely).
  Future<void> deleteMessageForEveryone({
    required String threadId,
    required String messageId,
  });

  /// Delete all messages in a thread (used when deleting the thread).
  Future<void> deleteAllMessages(String threadId);
}

abstract class MediaRepository {
  /// Upload an encrypted media blob to Firebase Storage.
  /// Returns the Storage path.
  Future<String> uploadEncryptedMedia({
    required String threadId,
    required String messageId,
    required String filename,
    required Uint8List encryptedBytes,
  });

  /// Download an encrypted media blob.
  Future<Uint8List> downloadEncryptedMedia(String storagePath);

  /// Delete encrypted media from Firebase Storage.
  Future<void> deleteMedia(String storagePath);

  /// Delete all media in a thread folder.
  Future<void> deleteThreadMedia(String threadId);
}
