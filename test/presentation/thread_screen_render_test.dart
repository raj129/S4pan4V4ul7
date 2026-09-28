import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/chat_vault_bridge.dart';
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/entities/chat_thread.dart';
import 'package:photo_vault/domain/entities/chat_user.dart';
import 'package:photo_vault/domain/entities/message_metadata.dart';
import 'package:photo_vault/domain/entities/message_reply.dart';
import 'package:photo_vault/domain/entities/user_presence.dart';
import 'package:photo_vault/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/domain/repositories/message_repository.dart';
import 'package:photo_vault/domain/repositories/outbox_repository.dart';
import 'package:photo_vault/domain/repositories/presence_repository.dart';
import 'package:photo_vault/domain/repositories/thread_repository.dart';
import 'package:photo_vault/domain/repositories/typing_repository.dart';
import 'package:photo_vault/domain/repositories/user_repository.dart';
import 'package:photo_vault/presentation/screens/chat_screens/thread_screen.dart';
import 'package:photo_vault/presentation/state/chat/active_thread_cubit.dart';
import 'package:photo_vault/presentation/widgets/chat/chat_bubble_shape.dart';
import 'package:photo_vault/presentation/widgets/chat/chat_media_preview.dart';
import 'package:photo_vault/presentation/widgets/chat/message_bubble.dart';

class _Crypto implements ChatCryptoService {
  @override
  Future<String> encryptMessage({
    required String threadId,
    required String plaintext,
  }) async => plaintext;

  @override
  Future<String> decryptMessage({
    required String threadId,
    required String encryptedB64,
  }) async => encryptedB64;

  @override
  Future<Uint8List> searchKey(String threadId) async => Uint8List(32);

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not needed');
}

class _Messages implements MessageRepository {
  final live = StreamController<List<ChatMessage>>.broadcast();

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId, {int limit = 30}) =>
      live.stream;

  @override
  Future<List<ChatMessage>> loadBefore({
    required String threadId,
    required DateTime before,
    int limit = 30,
  }) async => const [];

  @override
  Future<List<ChatMessage>> loadAfter({
    required String threadId,
    required DateTime after,
    int limit = 100,
  }) async => const [];

  /// Never acknowledges, so the sent message stays pending on screen.
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
  }) => Completer<ChatMessage>().future;

  @override
  Future<void> markRead({
    required String threadId,
    required List<String> messageIds,
    required String uid,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not needed');
}

class _Threads implements ThreadRepository {
  @override
  Future<void> resetUnread({
    required String threadId,
    required String uid,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not needed');
}

class _Typing implements TypingRepository {
  @override
  Stream<bool> watchTyping({
    required String threadId,
    required String otherUid,
  }) => const Stream.empty();

  @override
  Future<void> setTyping({
    required String threadId,
    required String uid,
    required bool isTyping,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not needed');
}

class _Presence implements PresenceRepository {
  @override
  Stream<UserPresence> watch(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not needed');
}

class _Outbox implements OutboxRepository {
  final Map<String, OutboxItem> items = {};

  @override
  Future<void> enqueue(OutboxItem item) async => items[item.messageId] = item;

  @override
  Future<List<OutboxItem>> pending() async => items.values.toList();

  @override
  Future<List<OutboxItem>> pendingForThread(String threadId) async =>
      items.values.where((i) => i.threadId == threadId).toList();

  @override
  Future<void> remove(String messageId) async => items.remove(messageId);

  @override
  Future<void> markFailed(String messageId, String error) async {}
}

class _Unused implements UserRepository, MediaRepository, ChatVaultBridge {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not needed');
}

ChatMessage _msg(String id, String text, {String sender = 'other'}) =>
    ChatMessage(
      messageId: id,
      threadId: 't',
      senderId: sender,
      encryptedText: text,
      sentAt: DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
      deletedFor: const [],
    );

void main() {
  test('bubble shape tolerates a rect narrower than its tail', () {
    for (final isMine in [true, false]) {
      final shape = ChatBubbleShape(isMine: isMine);
      expect(() => shape.getOuterPath(Rect.zero), returnsNormally);
      expect(
        () => shape.getOuterPath(const Rect.fromLTWH(0, 0, 4, 2)),
        returnsNormally,
      );
    }
  });

  testWidgets('thread screen renders received and sent messages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final messages = _Messages();
    final unused = _Unused();
    final cubit = ActiveThreadCubit(
      messageRepository: messages,
      threadRepository: _Threads(),
      userRepository: unused,
      typingRepository: _Typing(),
      presenceRepository: _Presence(),
      mediaRepository: unused,
      messageCache: const NoopMessageCacheRepository(),
      outbox: _Outbox(),
      cryptoService: _Crypto(),
      myUid: 'me',
    );
    final thread = ChatThread(
      threadId: 't',
      participantIds: const ['me', 'other'],
      lastMessage: '',
      createdAt: DateTime.utc(2024),
      lastMessageAt: DateTime.utc(2024),
      unreadCounts: const {},
    );
    final other = ChatUser(
      uid: 'other',
      email: 'other@example.com',
      displayName: 'Other',
      publicKey: '',
      createdAt: DateTime.utc(2024),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: cubit,
          child: ThreadScreen(
            thread: thread,
            otherUser: other,
            mediaLoader: ChatMediaLoader(
              mediaRepository: unused,
              cryptoService: _Crypto(),
            ),
            vaultBridge: unused,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    messages.live.add([_msg('m1', 'hello there')]);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MessageBubble), findsOneWidget);
    expect(tester.getSize(find.byType(MessageBubble)).width, greaterThan(100));
    expect(
      find.textContaining('hello there', findRichText: true),
      findsOneWidget,
    );

    // Not awaited: delivery never completes, so the message stays pending.
    unawaited(cubit.sendText('my reply'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(find.textContaining('my reply', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);

    await cubit.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
