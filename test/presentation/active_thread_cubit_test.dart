import 'dart:async';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/application/services/image_compressor.dart';
import 'package:photo_vault/domain/entities/chat_message.dart';
import 'package:photo_vault/domain/entities/chat_thread.dart';
import 'package:photo_vault/domain/entities/chat_user.dart';
import 'package:photo_vault/domain/entities/message_metadata.dart';
import 'package:photo_vault/domain/entities/message_reply.dart';
import 'package:photo_vault/domain/entities/user_presence.dart';
import 'package:photo_vault/domain/repositories/chat_search_index_repository.dart';
import 'package:photo_vault/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/domain/repositories/message_repository.dart';
import 'package:photo_vault/domain/repositories/outbox_repository.dart';
import 'package:photo_vault/domain/repositories/presence_repository.dart';
import 'package:photo_vault/domain/repositories/thread_repository.dart';
import 'package:photo_vault/domain/repositories/typing_repository.dart';
import 'package:photo_vault/domain/repositories/user_repository.dart';
import 'package:photo_vault/presentation/state/chat/active_thread_cubit.dart';
import 'package:photo_vault/presentation/state/chat/media_send_status.dart';

import '../helpers/memory_chat_search_index.dart';
import '../helpers/memory_message_cache.dart';

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
  Future<Uint8List> searchKey(String threadId) async =>
      Uint8List.fromList(List.filled(32, 7));

  @override
  Future<Uint8List> encryptMedia({
    required String threadId,
    required Uint8List bytes,
  }) async => bytes;

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

  /// Every message on the "server", for [loadAfter] catch-up queries.
  List<ChatMessage> server = const [];
  int loadAfterCalls = 0;

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
  Future<List<ChatMessage>> loadAfter({
    required String threadId,
    required DateTime after,
    int limit = 100,
  }) async {
    loadAfterCalls++;
    final newer = server.where((m) => m.sentAt.isAfter(after)).toList()
      ..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    return newer.take(limit).toList();
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
      mediaMeta: mediaMeta,
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

  /// Simulates an offline write that the server never acknowledges.
  bool hangResetUnread = false;

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
  Future<void> resetUnread({required String threadId, required String uid}) =>
      hangResetUnread ? Completer<void>().future : Future<void>.value();

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
  late _FakeMediaRepository media;
  late StreamController<List<ConnectivityResult>> connectivity;
  late Map<String, Uint8List> seeded;
  late List<MediaSendStatus> progressSeen;

  ActiveThreadCubit build({
    Stream<List<ConnectivityResult>>? connectivityStream,
    MessageCacheRepository messageCache = const NoopMessageCacheRepository(),
    ChatSearchIndexRepository searchIndex =
        const NoopChatSearchIndexRepository(),
  }) => ActiveThreadCubit(
    messageRepository: messages,
    threadRepository: threads,
    userRepository: _FakeUserRepository(),
    typingRepository: _FakeTypingRepository(),
    presenceRepository: _FakePresenceRepository(),
    mediaRepository: media,
    messageCache: messageCache,
    searchIndex: searchIndex,
    outbox: outbox,
    cryptoService: _PassThroughCrypto(),
    myUid: 'me',
    connectivityStream: connectivityStream,
    onMediaReady: (path, bytes) => seeded[path] = bytes,
  );

  setUp(() {
    messages = _FakeMessageRepository();
    threads = _FakeThreadRepository();
    outbox = _MemoryOutbox();
    media = _FakeMediaRepository();
    seeded = {};
    progressSeen = [];
    connectivity = StreamController<List<ConnectivityResult>>.broadcast();
    cubit = build();
    cubit.stream.listen((state) {
      if (state is ActiveThreadLoaded) {
        progressSeen.addAll(state.uploadProgress.values);
      }
    });
  });

  tearDown(() async {
    await cubit.close();
    await connectivity.close();
  });

  Future<void> open() async {
    await cubit.openThread(thread: _thread, otherUser: _other);
  }

  group('offline', () {
    test('opening a thread does not wait for unacknowledged writes', () async {
      threads.hangResetUnread = true;
      await open().timeout(const Duration(seconds: 1));

      messages.emitLive([_msg('cached', 2)]);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.messages.map((m) => m.messageId), ['cached']);
    });
  });

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
      expect(state.messages.map((m) => m.messageId).toList(), ['new', 'old']);
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

  group('history visibility', () {
    late MemoryMessageCache cache;

    setUp(() async {
      cache = MemoryMessageCache();
      await cubit.close();
      cubit = build(messageCache: cache);
    });

    Future<List<String>> shownAfter(List<ChatMessage> live) async {
      await open();
      messages.emitLive(live);
      await Future<void>.delayed(Duration.zero);
      return (cubit.state as ActiveThreadLoaded).messages
          .map((m) => m.messageId)
          .toList();
    }

    test('cleared messages stay hidden and are not re-cached', () async {
      cache.cleared['me_other'] = DateTime.utc(2024, 1, 3);

      final shown = await shownAfter([_msg('old', 2), _msg('new', 4)]);

      expect(shown, ['new']);
      await Future<void>.delayed(Duration.zero);
      expect(cache.rows.keys, ['new']);
    });

    test('server history before the horizon is hidden', () async {
      cache.horizon = DateTime.utc(2024, 1, 3);

      expect(await shownAfter([_msg('old', 2), _msg('new', 4)]), ['new']);
    });

    test('restored messages before the horizon stay visible', () async {
      cache.horizon = DateTime.utc(2024, 1, 3);
      await cache.save([_msg('restored', 2)]);

      final shown = await shownAfter([
        _msg('restored', 2),
        _msg('hidden', 1),
        _msg('new', 4),
      ]);

      expect(shown, ['new', 'restored']);
    });

    test('scrolling up never pages in hidden server history', () async {
      cache.horizon = DateTime.utc(2024, 1, 3);
      messages.history = [_msg('hidden', 1)];
      await shownAfter([_msg('new', 4)]);

      await cubit.loadOlderMessages();

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.messages.map((m) => m.messageId), ['new']);
      expect(state.hasMore, isFalse);
    });
  });

  group('search', () {
    late MemoryMessageCache cache;
    late MemoryChatSearchIndex index;

    Future<void> settle() =>
        Future<void>.delayed(const Duration(milliseconds: 700));

    ChatMessage at(String id, DateTime sentAt, {String? text}) => ChatMessage(
      messageId: id,
      threadId: 'me_other',
      senderId: 'other',
      encryptedText: text ?? 'text-$id',
      sentAt: sentAt,
      deletedFor: const [],
    );

    /// A year of history, one message per hour, with a single "needle".
    List<ChatMessage> history({int count = 400, int needleAt = 100}) => [
      for (var i = 0; i < count; i++)
        at(
          'h$i',
          DateTime.utc(2023, 1, 1).add(Duration(hours: i)),
          text: i == needleAt ? 'the blue needle' : 'filler $i',
        ),
    ];

    Future<void> openWith(List<ChatMessage> cached) async {
      await cubit.close();
      cache = MemoryMessageCache();
      index = MemoryChatSearchIndex(cache);
      await cache.save(cached);
      cubit = build(messageCache: cache, searchIndex: index);
      await open();
      messages.emitLive([_msg('a', 1), _msg('b', 2), _msg('c', 3)]);
      await settle();
    }

    setUp(() => openWith(const []));

    test('highlights matches without filtering the timeline', () async {
      cubit.setSearchQuery('text-b');
      await settle();

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.visibleMessages, hasLength(3));
      expect(state.searchMatchIds, ['b']);
      expect(state.currentMatchId, 'b');
    });

    test('is case-insensitive and clears back to no matches', () async {
      cubit.setSearchQuery('TEXT-C');
      await settle();
      expect((cubit.state as ActiveThreadLoaded).searchMatchIds, ['c']);

      cubit.clearSearch();
      final state = cubit.state as ActiveThreadLoaded;
      expect(state.searchMatchIds, isEmpty);
      expect(state.currentMatchId, isNull);
      expect(state.visibleMessages, hasLength(3));
    });

    test('matches word prefixes', () async {
      cubit.setSearchQuery('tex');
      await settle();
      expect((cubit.state as ActiveThreadLoaded).searchMatchIds, [
        'c',
        'b',
        'a',
      ]);
    });

    test('starts at the newest match and steps within bounds', () async {
      cubit.setSearchQuery('text');
      await settle();

      var state = cubit.state as ActiveThreadLoaded;
      expect(state.searchMatchIds, ['c', 'b', 'a']);
      expect(state.currentMatchId, 'c');

      await cubit.previousMatch();
      expect((cubit.state as ActiveThreadLoaded).currentMatchId, 'c');

      await cubit.nextMatch();
      await cubit.nextMatch();
      await cubit.nextMatch();
      state = cubit.state as ActiveThreadLoaded;
      expect(state.currentMatchId, 'a');
      expect(state.currentMatchIndex, 2);

      await cubit.previousMatch();
      expect((cubit.state as ActiveThreadLoaded).currentMatchId, 'b');
    });

    test('reports no matches without hiding messages', () async {
      cubit.setSearchQuery('zzz');
      await settle();

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.searchMatchIds, isEmpty);
      expect(state.currentMatchId, isNull);
      expect(state.searchInProgress, isFalse);
      expect(state.visibleMessages, hasLength(3));
    });

    test('never matches messages deleted for me', () async {
      messages.emitLive([
        ChatMessage(
          messageId: 'gone',
          threadId: 'me_other',
          senderId: 'other',
          encryptedText: 'secret words',
          sentAt: DateTime.utc(2024, 1, 4),
          deletedFor: const ['me'],
        ),
      ]);
      await settle();

      cubit.setSearchQuery('secret');
      await settle();
      expect((cubit.state as ActiveThreadLoaded).searchMatchIds, isEmpty);
    });

    test('lands on a months-old match that was never loaded', () async {
      await openWith(history());

      // Only the newest cached page was paged in on open.
      var state = cubit.state as ActiveThreadLoaded;
      expect(state.messages.any((m) => m.messageId == 'h100'), isFalse);
      expect(state.indexingProgress, isNull, reason: 'backfill finished');

      cubit.setSearchQuery('needle');
      await settle();

      state = cubit.state as ActiveThreadLoaded;
      expect(state.searchMatchIds, ['h100']);
      expect(state.currentMatchId, 'h100');
      expect(state.scrollRequest?.messageId, 'h100');
      expect(state.isDetached, isTrue);
      // The match is shown in context, in a bounded window.
      final ids = state.messages.map((m) => m.messageId).toList();
      expect(ids, containsAll(['h99', 'h100', 'h101']));
      expect(ids.length, lessThanOrEqualTo(81));
      expect(ids, isNot(contains('c')));
    });

    test('scrolling newer from a jump reattaches to the live chat', () async {
      await openWith(history());
      await cubit.jumpToMessage('h100');
      expect((cubit.state as ActiveThreadLoaded).isDetached, isTrue);

      for (var i = 0; i < 20; i++) {
        final state = cubit.state as ActiveThreadLoaded;
        if (!state.isDetached) break;
        expect(state.messages.length, lessThanOrEqualTo(300));
        await cubit.loadNewerMessages();
      }

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.isDetached, isFalse);
      expect(state.messages.first.messageId, 'c');
      expect(state.messages.length, lessThanOrEqualTo(300));
    });

    test('jump to latest returns to the live chat', () async {
      await openWith(history());
      await cubit.jumpToMessage('h100');

      await cubit.jumpToLatest();

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.isDetached, isFalse);
      expect(state.messages.first.messageId, 'c');
      expect(state.scrollRequest?.messageId, isNull);
    });

    test('counts new arrivals while viewing older history', () async {
      await openWith(history());
      await cubit.jumpToMessage('h100');

      messages.emitLive([
        _msg('a', 1),
        _msg('b', 2),
        _msg('c', 3),
        _msg('d', 4),
        _msg('mine', 5, sender: 'me'),
      ]);
      await Future<void>.delayed(Duration.zero);

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.newWhileDetached, 1);
      expect(state.messages.any((m) => m.messageId == 'd'), isFalse);
    });

    test('jumps to a date and to a scrollbar position', () async {
      await openWith(history());

      expect(await cubit.jumpToDate(DateTime(2023, 1, 5)), isTrue);
      var state = cubit.state as ActiveThreadLoaded;
      final target = state.messages.firstWhere(
        (m) => m.messageId == state.scrollRequest!.messageId,
      );
      expect(target.sentAt.isBefore(DateTime.utc(2023, 1, 4)), isFalse);
      expect(state.isDetached, isTrue);

      await cubit.jumpToFraction(0);
      state = cubit.state as ActiveThreadLoaded;
      expect(state.scrollRequest?.messageId, 'h0');

      await cubit.jumpToFraction(1);
      state = cubit.state as ActiveThreadLoaded;
      expect(state.isDetached, isFalse);
    });

    test('scrolling far back keeps the timeline bounded', () async {
      messages.history = [
        for (var i = 0; i < 400; i++)
          at('s$i', DateTime.utc(2023, 12, 1).subtract(Duration(hours: i))),
      ];
      await openWith(const []);

      for (var i = 0; i < 14; i++) {
        await cubit.loadOlderMessages();
      }

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.messages.length, lessThanOrEqualTo(300));
      expect(state.isDetached, isTrue);
      expect(state.messages.any((m) => m.messageId == 'c'), isFalse);
    });

    test('catches the cache up with messages missed while closed', () async {
      await cubit.close();
      cache = MemoryMessageCache();
      index = MemoryChatSearchIndex(cache);
      await cache.save([at('seen', DateTime.utc(2023, 6, 1))]);
      messages.server = [
        for (var i = 0; i < 150; i++)
          at(
            'm$i',
            DateTime.utc(2023, 6, 2).add(Duration(hours: i)),
            text: i == 42 ? 'missed needle' : 'filler',
          ),
      ];
      cubit = build(messageCache: cache, searchIndex: index);
      await open();
      await settle();

      expect(cache.rows.length, 151);
      expect(messages.loadAfterCalls, 2);

      cubit.setSearchQuery('needle');
      await settle();
      expect((cubit.state as ActiveThreadLoaded).searchMatchIds, ['m42']);
    });

    test('catch-up never pulls in history before the horizon', () async {
      await cubit.close();
      cache = MemoryMessageCache();
      index = MemoryChatSearchIndex(cache);
      cache.horizon = DateTime.utc(2023, 6, 10);
      await cache.save([at('restored', DateTime.utc(2023, 6, 1))]);
      messages.server = [
        at('hidden', DateTime.utc(2023, 6, 5)),
        at('visible', DateTime.utc(2023, 6, 11)),
      ];
      cubit = build(messageCache: cache, searchIndex: index);
      await open();
      await settle();

      expect(cache.rows.keys, unorderedEquals(['restored', 'visible']));
    });
  });

  group('outbox', () {
    test('a successful send leaves nothing queued', () async {
      await open();

      await cubit.sendText('hello');

      expect(outbox.items, isEmpty);
      expect(messages.sent.single.encryptedText, 'hello');
      expect(threads.unreadBumps, ['other']);
      expect(
        (cubit.state as ActiveThreadLoaded).messages.single.status,
        MessageStatus.sent,
      );
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

    test(
      'discard drops a failed message from the queue and the list',
      () async {
        await open();
        messages.failNextSend = StateError('offline');
        await cubit.sendText('hello');
        final queuedId = outbox.items.keys.single;

        await cubit.discardMessage(queuedId);

        expect(outbox.items, isEmpty);
        expect((cubit.state as ActiveThreadLoaded).messages, isEmpty);
      },
    );

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

    test(
      'reconnect flushes queued messages and clears offline state',
      () async {
        await cubit.close();
        cubit = build(connectivityStream: connectivity.stream);
        await open();
        messages.emitLive(const []);
        await Future<void>.delayed(Duration.zero);

        connectivity.add(const [ConnectivityResult.none]);
        await Future<void>.delayed(Duration.zero);
        expect((cubit.state as ActiveThreadLoaded).isOffline, isTrue);

        messages.failNextSend = StateError('offline');
        await cubit.sendText('queued while offline');
        expect(outbox.items, hasLength(1));

        connectivity.add(const [ConnectivityResult.wifi]);
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        final state = cubit.state as ActiveThreadLoaded;
        expect(state.isOffline, isFalse);
        expect(outbox.items, isEmpty);
        expect(messages.sent.single.encryptedText, 'queued while offline');
        expect(state.messages.single.status, MessageStatus.sent);
      },
    );

    test('an empty message is not queued', () async {
      await open();
      await cubit.sendText('   ');

      expect(outbox.items, isEmpty);
      expect(messages.sent, isEmpty);
    });
  });

  group('attachments', () {
    test('a document is sent with its name only in the encrypted body', () async {
      await open();

      await cubit.sendMedia(
        messageId: 'doc1',
        rawBytes: [1, 2, 3],
        type: MessageType.file,
        filename: 'report.pdf',
      );

      final sent = messages.sent.single;
      expect(sent.mediaType, MessageType.file);
      expect(sent.encryptedText, '📎 report.pdf');
      expect(sent.mediaRef, 'chat_media/me_other/doc1/doc1.bin.enc');
      // The storage object name must not reveal the file type.
      expect(media.uploadedNames.single, 'doc1.bin.enc');
      expect(sent.mediaMeta?.sizeBytes, 3);
      expect(sent.mediaMeta?.filename, isNull);
      expect(threads.unreadBumps, ['other']);
      expect(outbox.items, isEmpty);
    });

    test('an image records its dimensions for the placeholder', () async {
      await open();
      final png = img.encodePng(img.Image(width: 4, height: 2));

      await cubit.sendMedia(
        messageId: 'img1',
        rawBytes: png,
        type: MessageType.image,
      );

      final meta = messages.sent.single.mediaMeta!;
      expect(meta.width, 4);
      expect(meta.height, 2);
      expect(meta.sizeBytes, png.length);
      // The preview is uploaded before the full-size object.
      expect(media.uploadedNames, ['img1.thumb.enc', 'img1.jpg.enc']);
      expect(meta.thumbRef, 'chat_media/me_other/img1/img1.thumb.enc');
    });

    test('a lower quality shrinks what is uploaded', () async {
      await open();
      // Detailed enough that JPEG at 800 px is clearly smaller than the PNG.
      final source = img.Image(width: 2000, height: 1000);
      for (var y = 0; y < source.height; y++) {
        for (var x = 0; x < source.width; x++) {
          source.setPixelRgb(x, y, x % 256, y % 256, (x * y) % 256);
        }
      }
      final png = img.encodePng(source);

      await cubit.sendMedia(
        messageId: 'img2',
        rawBytes: png,
        type: MessageType.image,
        quality: ImageQuality.low,
      );

      final meta = messages.sent.single.mediaMeta!;
      expect(meta.sizeBytes, lessThan(png.length));
      expect(meta.width, 800);
      expect(meta.height, 400);
    });

    test('the sender gets their own bytes without a download', () async {
      await open();
      final png = img.encodePng(img.Image(width: 4, height: 2));

      await cubit.sendMedia(
        messageId: 'img3',
        rawBytes: png,
        type: MessageType.image,
      );

      expect(
        seeded.keys,
        containsAll(<String>[
          'chat_media/me_other/img3/img3.thumb.enc',
          'chat_media/me_other/img3/img3.jpg.enc',
        ]),
      );
    });

    test('progress is published before compression starts', () async {
      await open();
      final png = img.encodePng(img.Image(width: 4, height: 2));

      await cubit.sendMedia(
        messageId: 'img4',
        rawBytes: png,
        type: MessageType.image,
      );

      // The bubble must exist while the photo is still being prepared,
      // otherwise tapping send looks like it did nothing.
      expect(
        progressSeen.first.phase,
        MediaSendPhase.preparing,
        reason: 'the first status must precede compression',
      );
    });

    test('progress only ever moves forwards', () async {
      await open();
      final png = img.encodePng(img.Image(width: 4, height: 2));

      await cubit.sendMedia(
        messageId: 'img5',
        rawBytes: png,
        type: MessageType.image,
      );

      final fractions = [for (final s in progressSeen) s.progress];
      for (var i = 1; i < fractions.length; i++) {
        expect(
          fractions[i],
          greaterThanOrEqualTo(fractions[i - 1]),
          reason: 'the ring must not rewind between phases',
        );
      }
      expect(fractions.last, 1.0);
    });

    test('upload progress is published and then cleared', () async {
      await open();

      await cubit.sendMedia(
        messageId: 'doc2',
        rawBytes: [1, 2, 3],
        type: MessageType.file,
        filename: 'a.pdf',
      );

      // Reported while uploading…
      expect(
        progressSeen.any((s) => s.phase == MediaSendPhase.uploading),
        isTrue,
      );
      // …and gone once the message is sent.
      final state = cubit.state as ActiveThreadLoaded;
      expect(state.uploadProgress, isEmpty);
    });

    test('an oversized photo takes its own bubble back', () async {
      await open();
      // Compresses to something still over the limit, so the rejection
      // happens after the bubble is already on screen.
      final huge = Uint8List(ActiveThreadCubit.maxAttachmentBytes + 1);

      await cubit.sendMedia(
        messageId: 'big2',
        rawBytes: huge,
        type: MessageType.image,
      );

      final state = cubit.state as ActiveThreadLoaded;
      expect(state.messages.where((m) => m.messageId == 'big2'), isEmpty);
      expect(state.uploadProgress, isEmpty);
      expect(outbox.items, isEmpty);
      expect(messages.sent, isEmpty);
    });

    test('a batch gives every photo its own message', () async {
      await open();
      final png = img.encodePng(img.Image(width: 4, height: 2));

      for (final id in ['b1', 'b2', 'b3']) {
        await cubit.sendMedia(
          messageId: id,
          rawBytes: png,
          type: MessageType.image,
        );
      }

      expect(messages.sent.map((m) => m.messageId), ['b1', 'b2', 'b3']);
      // Nothing is left showing progress once the batch is done.
      expect((cubit.state as ActiveThreadLoaded).uploadProgress, isEmpty);
    });

    test('one failed photo does not hold up the rest', () async {
      await open();
      final png = img.encodePng(img.Image(width: 4, height: 2));
      media.failOnMessageId = 'f2';

      for (final id in ['f1', 'f2', 'f3']) {
        await cubit.sendMedia(
          messageId: id,
          rawBytes: png,
          type: MessageType.image,
        );
      }

      expect(messages.sent.map((m) => m.messageId), ['f1', 'f3']);
      expect((cubit.state as ActiveThreadLoaded).uploadProgress, isEmpty);
    });

    test('an attachment over the Storage limit is rejected up front', () async {
      await open();

      await cubit.sendMedia(
        messageId: 'big',
        rawBytes: Uint8List(ActiveThreadCubit.maxAttachmentBytes + 1),
        type: MessageType.file,
        filename: 'huge.zip',
      );

      expect(media.uploadedNames, isEmpty);
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
  /// Storage object names passed to [uploadEncryptedMedia].
  final List<String> uploadedNames = [];

  /// When set, uploads for this message id throw, to check that one bad photo
  /// in a batch does not stop the others.
  String? failOnMessageId;

  @override
  Future<String> uploadEncryptedMedia({
    required String threadId,
    required String messageId,
    required String filename,
    required Uint8List encryptedBytes,
    void Function(double progress)? onProgress,
  }) async {
    if (messageId == failOnMessageId) {
      throw Exception('upload refused');
    }
    uploadedNames.add(filename);
    onProgress?.call(0.5);
    onProgress?.call(1);
    return 'chat_media/$threadId/$messageId/$filename';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}
