import '../../domain/entities/chat_message.dart';
import '../../domain/entities/geo_share.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/thread_repository.dart';
import '../crypto/chat_crypto_service.dart';

/// Encrypts a pin / route / arrival payload and posts it to [threadId].
/// Shared by the UI and the headless background worker.
Future<void> sendGeoShareMessage({
  required ChatCryptoService crypto,
  required MessageRepository messages,
  required ThreadRepository threads,
  required String threadId,
  required String senderId,
  required String recipientUid,
  required GeoShare share,
}) async {
  final encrypted = await crypto.encryptMessage(
    threadId: threadId,
    plaintext: share.encode(),
  );
  final sent = await messages.sendMessage(
    threadId: threadId,
    senderId: senderId,
    encryptedText: encrypted,
    mediaType: switch (share.kind) {
      GeoShareKind.pin => MessageType.pin,
      GeoShareKind.route => MessageType.route,
      GeoShareKind.arrival => MessageType.arrival,
    },
  );
  await threads.updateLastMessage(
    threadId: threadId,
    preview: share.preview,
    sentAt: sent.sentAt,
  );
  await threads.incrementUnread(
    threadId: threadId,
    recipientUid: recipientUid,
  );
}
