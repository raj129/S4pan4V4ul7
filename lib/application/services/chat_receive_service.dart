import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../crypto/services/chat_crypto_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/message_cache_repository.dart';
import '../../domain/repositories/message_repository.dart';
import 'chat_media_cache.dart';

/// Background receipt processing never unlocks or imports into the vault.
class ChatReceiveService {
  ChatReceiveService({
    required this.messages,
    required this.messageCache,
    required this.media,
    required this.crypto,
    required this.cache,
    required this.currentUid,
    this.operationTimeout = const Duration(seconds: 45),
  });

  final MessageRepository messages;
  final MessageCacheRepository messageCache;
  final MediaRepository media;
  final ChatCryptoService crypto;
  final ChatMediaCache cache;
  final String? Function() currentUid;
  final Duration operationTimeout;

  void _checkAccount(String uid) {
    if (currentUid() != uid) throw const ChatReceiveAccountChanged();
  }

  Future<void> process({
    required String uid,
    required String threadId,
    required String messageId,
  }) async {
    _checkAccount(uid);
    final message = await messages
        .getMessage(threadId: threadId, messageId: messageId)
        .timeout(operationTimeout);
    if (message == null || message.isDeletedFor(uid)) return;
    if (message.threadId != threadId ||
        message.messageId != messageId ||
        !threadId.split('_').contains(uid)) {
      throw const FormatException('Invalid received message identity.');
    }
    // Authentication/key availability is checked before local receipts/cache.
    await crypto
        .decryptMessage(threadId: threadId, encryptedB64: message.encryptedText)
        .timeout(operationTimeout);
    _checkAccount(uid);
    final horizon = await messageCache.getHistoryHorizon();
    final cleared = await messageCache.getClearedBefore(threadId);
    if ((horizon != null && !message.sentAt.isAfter(horizon)) ||
        (cleared != null && !message.sentAt.isAfter(cleared))) {
      return;
    }
    await messageCache.save([message]);
    _checkAccount(uid);
    await messages
        .markDelivered(threadId: threadId, messageIds: [messageId], uid: uid)
        .timeout(operationTimeout);
    if (message.senderId == uid) return;

    if (message.mediaType != MessageType.image &&
        message.mediaType != MessageType.video) {
      return;
    }
    final refs = <String>{
      if (message.mediaMeta?.thumbRef case final String thumb) thumb,
      if (message.mediaRef case final String full) full,
    };
    for (final ref in refs) {
      _checkAccount(uid);
      if (!ref.startsWith('chat_media/$threadId/$messageId/')) {
        throw const FormatException('Invalid attachment path.');
      }
      final key = '$uid:$ref';
      if (await cache.wasMoved(key)) continue;
      final existing = await cache.read(key);
      if (existing != null) {
        // A cached object is not necessarily authenticated (legacy cache).
        try {
          final plain = await crypto
              .decryptMedia(threadId: threadId, encryptedBytes: existing)
              .timeout(operationTimeout);
          plain.fillRange(0, plain.length, 0);
          continue;
        } on FormatException {
          await cache.remove(key);
        } on RangeError {
          await cache.remove(key);
        } on SecretBoxAuthenticationError {
          await cache.remove(key);
        }
      }
      final ciphertext = await media
          .downloadEncryptedMedia(ref)
          .timeout(operationTimeout);
      if (ciphertext.isEmpty) {
        throw const FormatException('Received attachment is empty.');
      }
      final Uint8List plain = await crypto
          .decryptMedia(threadId: threadId, encryptedBytes: ciphertext)
          .timeout(operationTimeout);
      try {
        if (plain.isEmpty) {
          throw const FormatException('Received attachment is empty.');
        }
        _checkAccount(uid);
        await cache.write(key, ciphertext);
      } finally {
        plain.fillRange(0, plain.length, 0);
      }
    }
  }
}

class ChatReceiveAccountChanged implements Exception {
  const ChatReceiveAccountChanged();
  @override
  String toString() => 'Chat account changed during receipt processing.';
}
