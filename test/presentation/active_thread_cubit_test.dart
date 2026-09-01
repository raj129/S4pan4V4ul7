import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
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
import 'package:photo_vault/presentation/state/chat/active_thread_cubit.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Crypto that leaves text alone, so assertions read as plaintext.
class _PassThroughCrypto implements ChatCryptoService {
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
  Future<void> deriveAndStoreThreadKey({
    required String threadId,
    required String otherPublicKeyB64,
  }) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

class _FakeMessageRepository implements MessageRepository {
  /// Older messages served by [loadBefore], newest first.
  List<ChatMessage> history = const [];

  final _live = StreamController<List<ChatMessage>>.broadcast();

  /// Sends that reached the "server".
  final List<ChatMessage> sent = [];

  /// When set, the next send throws — used to simulate being offline.
  Object? failNextSend;

  int loadBeforeCalls = 0;

  void emitLive(List<ChatMessage> messages) => _live.add(messages);

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId, {int limit = 30}) =>
      _live.stream;

  @override
  Future<List<ChatMessage>> loadBefore({
    required String threadId,
    required DateTime before,
    int limit = 30,
  }) async {
    loadBeforeCalls++;
    return history.where((m) => m.sentAt.isBefore(before)).take(limit).toList();
  }

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
    final failure = failNextSend;
    if (failure != null) {
      failNextSend = null;
      throw failure;
    }
    final msg = ChatMessage(
      messageId: messageId ?? 'generated',
      threadId: threadId,
      senderId: senderId,
      encryptedText: encryptedText,
      sentAt: DateTime.utc(2024, 1, 2),
      deletedFor: const [],
      mediaRef: mediaRef,
      mediaType: mediaType,
      replyTo: replyTo,
      isForwarded: isForwarded,
      status: MessageStatus.sent,
    );
    sent.add(msg);
    return msg;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

class _FakeThreadRepository implements ThreadRepository {
  final List<String> previews = [];
  final List<String> unreadBumps = [];

  @override
  Future<void> updateLastMessage({
    required String threadId,
    required String preview,
    required DateTime sentAt,
  }) async => previews.add(preview);

  @override
  Future<void> incrementUnread({
    required String threadId,
    required String recipientUid,
  }) async => unreadBumps.add(recipientUid);

  @override
  Future<void> resetUnread({
    required String threadId,
    required String uid,
  }) async {}

  @override
  Stream<List<ChatThread>> watchThreadsForUser(String uid) =>
      const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

class _FakeTypingRepository implements TypingRepository {
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

class _FakePresenceRepository implements PresenceRepository {
  @override
  Stream<UserPresence> watch(String uid) => const Stream.empty();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

class _MemoryOutbox implements OutboxRepository {
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
  Future<void> markFailed(String messageId, String error) async {
    final item = items[messageId];
    if (item != null) {
      items[messageId] = item.copyWith(
        attempts: item.attempts + 1,
        lastError: error,
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ChatMessage _msg(String id, int day, {String sender = 'other'}) => ChatMessage(
  messageId: id,
  threadId: 'me_other',
  senderId: sender,
  encryptedText: 'text-$id',
  sentAt: DateTime.utc(2024, 1, day),
  deletedFor: const [],
);

final _thread = ChatThread(
  threadId: 'me_other',
  participantIds: const ['me', 'other'],
  lastMessage: '',
  createdAt: DateTime.utc(2024),
  lastMessageAt: DateTime.utc(2024),
  unreadCounts: const {},
);

final _other = ChatUser(
  uid: 'other',
  email: 'other@example.com',
  displayName: 'Other',
  publicKey: '',
  createdAt: DateTime.utc(2024),
);

void main() {
  late _FakeMessageRepository messages;
  late _FakeThreadRepository threads;
  late _MemoryOutbox outbox;
  late ActiveThreadCubit cubit;

  ActiveThreadCubit build() => ActiveThreadCubit(
    messageRepository: messages,
    threadRepository: threads,
    userRepository: _FakeUserRepository(),
    typingRepository: _FakeTypingRepository(),
    presenceRepository: _FakePresenceRepository(),
    mediaRepository: _FakeMediaRepository(),
    messageCache: const NoopMessageCacheRepository(),
    outbox: outbox,
    cryptoService: _PassThroughCrypto(),
    myUid: 'me',
  );

  setUp(() {
    messages = _FakeMessageRepository();
    threads = _FakeThreadRepository();
    outbox = _MemoryOutbox();
    cubit = build();
  });

  tearDown(() => cubit.close());

  Future<void> open() async {
    await cubit.openThread(thread: _thread, otherUser: _other);
  }

  group('buffer merging', () {
    test('a live snapshot does not discard paged-in history', () async {
      messages.history = [_msg('old', 1)];
      await open();
      messages.emitLive([_msg('new', 5)]);
      await Future<void>.delayed(Duration.zero);

      await cubit.loadOlderMessages();

      // The live query only ever returns the newest page. Assigning its
      // snapshots over the buffer used to silently drop everything pagination
      // had fetched, making history un-scrollable.
      messages.emitLive([_msg('new', 5)]);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as ActiveThreadLoaded;
      expect(
        state.messages.map((m) => m.messageId).toList(),
        ['new', 'old'],
      );
    });

    test('orders newest first', () async {
      await open();
      messages.emitLive([_msg('a', 1), _msg('c', 3), _msg('b', 2)]);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.messages.map((m) => m.messageId).toList(), ['c', 'b', 'a']);
    });

    test('an empty older page marks the start of the conversation', () async {
      messages.history = [];
      await open();
      messages.emitLive([_msg('a', 5)]);
      await Future<void>.delayed(Duration.zero);

      await cubit.loadOlderMessages();

      expect((cubit.state as ActiveThreadLoaded).hasMore, isFalse);

      // Further scrolls must not keep hammering the network.
      final before = messages.loadBeforeCalls;
      await cubit.loadOlderMessages();
      expect(messages.loadBeforeCalls, before);
    });
  });

  group('search', () {
    setUp(() async {
      await open();
      messages.emitLive([
        _msg('a', 1),
        _msg('b', 2),
        _msg('c', 3),
      ]);
      await Future<void>.delayed(Duration.zero);
    });

    test('filters the decrypted buffer', () {
      cubit.setSearchQuery('text-b');

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.visibleMessages.map((m) => m.messageId).toList(), ['b']);
      // The full buffer is untouched, so clearing restores instantly.
      expect(state.messages, hasLength(3));
    });

    test('is case-insensitive and clears back to everything', () {
      cubit.setSearchQuery('TEXT-C');
      expect((cubit.state as ActiveThreadLoaded).visibleMessages, hasLength(1));

      cubit.clearSearch();
      expect((cubit.state as ActiveThreadLoaded).visibleMessages, hasLength(3));
    });
  });

  group('outbox', () {
    test('a successful send leaves nothing queued', () async {
      await open();

      await cubit.sendText('hello');

      expect(outbox.items, isEmpty);
      expect(messages.sent.single.encryptedText, 'hello');
      expect(threads.unreadBumps, ['other']);
    });

    test('a failed send stays queued and shows as failed', () async {
      await open();
      messages.failNextSend = StateError('offline');

      await cubit.sendText('hello');

      // The durable copy is the source of truth: losing it on failure would
      // lose the user's message.
      expect(outbox.items, hasLength(1));
      final shown = (cubit.state as ActiveThreadLoaded).messages.single;
      expect(shown.status, MessageStatus.failed);
      expect(shown.localDecryptedText, 'hello');
    });

    test('retry delivers a previously failed message', () async {
      await open();
      messages.failNextSend = StateError('offline');
      await cubit.sendText('hello');
      final queuedId = outbox.items.keys.single;

      await cubit.retryMessage(queuedId);

      expect(outbox.items, isEmpty);
      expect(messages.sent.single.messageId, queuedId);
    });

    test('discard drops a failed message from the queue and the list',
        () async {
      await open();
      messages.failNextSend = StateError('offline');
      await cubit.sendText('hello');
      final queuedId = outbox.items.keys.single;

      await cubit.discardMessage(queuedId);

      expect(outbox.items, isEmpty);
      expect((cubit.state as ActiveThreadLoaded).messages, isEmpty);
    });

    test('the delivered message replaces its optimistic copy', () async {
      await open();
      await cubit.sendText('hello');
      final id = messages.sent.single.messageId;

      messages.emitLive([messages.sent.single]);
      await Future<void>.delayed(Duration.zero);

      final shown = (cubit.state as ActiveThreadLoaded).messages;
      expect(shown, hasLength(1));
      expect(shown.single.messageId, id);
      expect(shown.single.status, MessageStatus.sent);
    });

    test('opening a thread flushes what was queued while offline', () async {
      await open();
      messages.failNextSend = StateError('offline');
      await cubit.sendText('queued while offline');
      expect(outbox.items, hasLength(1));

      // Re-opening simulates coming back to the conversation with a connection.
      await cubit.close();
      cubit = build();
      await open();
      await Future<void>.delayed(Duration.zero);

      expect(outbox.items, isEmpty);
      expect(messages.sent.single.encryptedText, 'queued while offline');
    });

    test('an empty message is not queued', () async {
      await open();
      await cubit.sendText('   ');

      expect(outbox.items, isEmpty);
      expect(messages.sent, isEmpty);
    });
  });
}

class _FakeUserRepository implements UserRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

class _FakeMediaRepository implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}
