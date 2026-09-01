import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_reply.dart';
import '../../domain/repositories/outbox_repository.dart';
import '../../storage/local_db/vault_database.dart';

/// Drift-backed send queue, sharing the existing vault database.
class DriftOutboxRepository implements OutboxRepository {
  DriftOutboxRepository(this._db);

  final VaultDatabase _db;

  @override
  Future<void> enqueue(OutboxItem item) {
    return _db.enqueueOutbox(
      OutboxMessagesCompanion(
        messageId: Value(item.messageId),
        threadId: Value(item.threadId),
        senderId: Value(item.senderId),
        encryptedText: Value(item.encryptedText),
        recipientUid: Value(item.recipientUid),
        preview: Value(item.preview),
        mediaType: Value(item.mediaType?.name),
        mediaRef: Value(item.mediaRef),
        replyJson: Value(
          item.replyTo == null
              ? null
              : jsonEncode(item.replyTo!.toFirestore()),
        ),
        queuedAtMs: Value(item.queuedAt.toUtc().millisecondsSinceEpoch),
        attempts: Value(item.attempts),
        lastError: Value(item.lastError),
      ),
    );
  }

  @override
  Future<List<OutboxItem>> pending() async =>
      (await _db.getOutboxEntries()).map(_toItem).toList();

  @override
  Future<List<OutboxItem>> pendingForThread(String threadId) async =>
      (await _db.getOutboxForThread(threadId)).map(_toItem).toList();

  @override
  Future<void> remove(String messageId) => _db.deleteOutboxEntry(messageId);

  @override
  Future<void> markFailed(String messageId, String error) =>
      _db.markOutboxFailure(messageId, error);

  OutboxItem _toItem(OutboxEntry row) => OutboxItem(
    messageId: row.messageId,
    threadId: row.threadId,
    senderId: row.senderId,
    encryptedText: row.encryptedText,
    recipientUid: row.recipientUid,
    preview: row.preview,
    mediaType: _parseMediaType(row.mediaType),
    mediaRef: row.mediaRef,
    replyTo: _parseReply(row.replyJson),
    queuedAt: DateTime.fromMillisecondsSinceEpoch(row.queuedAtMs, isUtc: true),
    attempts: row.attempts,
    lastError: row.lastError,
  );

  static MessageType? _parseMediaType(String? name) {
    if (name == null) return null;
    for (final type in MessageType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  static MessageReply? _parseReply(String? json) {
    if (json == null) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      return MessageReply.fromFirestore(decoded.cast<String, dynamic>());
    } catch (_) {
      // A malformed row must not block the whole queue; the message is still
      // delivered, just without its quoted header.
      return null;
    }
  }
}
