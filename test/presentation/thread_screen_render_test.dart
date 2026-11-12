import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/data/repositories/local_sticker_pack_repository.dart';
import 'package:photo_vault/core/integrations/chat_vault_bridge.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_thread.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_user.dart';
import 'package:photo_vault/features/chat/domain/entities/message_metadata.dart';
import 'package:photo_vault/features/chat/domain/entities/message_reply.dart';
import 'package:photo_vault/features/chat/domain/entities/user_presence.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/chat_draft_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/outbox_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/presence_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/thread_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/typing_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/user_repository.dart';
import 'package:photo_vault/features/chat/presentation/screens/thread_screen.dart';
import 'package:photo_vault/features/chat/presentation/state/active_thread_cubit.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_bubble_shape.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_media_picker.dart';
import 'package:photo_vault/features/chat/presentation/widgets/chat_media_preview.dart';
import 'package:photo_vault/features/chat/presentation/widgets/message_bubble.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';

class _Crypto implements ChatCryptoService {
  @override
  Future<String> encryptMessage({
    required String threadId,
    required String plaintext,
  }) async => 'cipher:$plaintext';

  @override
  Future<String> decryptMessage({
    required String threadId,
    required String encryptedB64,
  }) async => encryptedB64.startsWith('cipher:')
      ? encryptedB64.substring('cipher:'.length)
      : encryptedB64;

  @override
  Future<Uint8List> searchKey(String threadId) async => Uint8List(32);

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not needed');
}

class _Messages implements MessageRepository {
  // ignore: close_sinks - test fake lives for the whole test.
  final live = StreamController<List<ChatMessage>>.broadcast();
  final editedTexts = <String>[];
  Completer<List<ChatMessage>>? nextOlderPage;
  int loadBeforeCalls = 0;

  final deletedForUser = <({String threadId, String messageId, String uid})>[];
  final deletedForEveryone = <({String threadId, String messageId})>[];

  @override
  Future<void> deleteMessageForUser({
    required String threadId,
    required String messageId,
    required String uid,
  }) async {
    deletedForUser.add((threadId: threadId, messageId: messageId, uid: uid));
  }

  @override
  Future<void> deleteMessageForEveryone({
    required String threadId,
    required String messageId,
  }) async {
    deletedForEveryone.add((threadId: threadId, messageId: messageId));
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String threadId, {int limit = 30}) =>
      live.stream;

  @override
  Future<List<ChatMessage>> loadBefore({
    required String threadId,
    required DateTime before,
    int limit = 30,
  }) {
    loadBeforeCalls++;
    final pendingPage = nextOlderPage;
    nextOlderPage = null;
    if (pendingPage != null) return pendingPage.future;
    return Future.value(const []);
  }

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
    DateTime? sentAt,
    String? mediaRef,
    MessageType? mediaType,
    String? liveLocationSessionId,
    String? sharedNoteId,
    MediaMeta? mediaMeta,
    MessageReply? replyTo,
    bool isForwarded = false,
  }) => Completer<ChatMessage>().future;

  @override
  Future<void> editMessage({
    required String threadId,
    required String messageId,
    required String encryptedText,
  }) async {
    editedTexts.add(encryptedText);
  }

  @override
  Future<void> markRead({
    required String threadId,
    required List<String> messageIds,
    required String uid,
  }) async {}

  @override
  Future<void> markDelivered({
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

class _Drafts implements ChatDraftRepository {
  final Map<String, String> values = {};

  @override
  Future<String?> load(String threadId) async => values[threadId];

  @override
  Future<void> save(String threadId, String encryptedText) async {
    values[threadId] = encryptedText;
  }

  @override
  Future<void> delete(String threadId) async {
    values.remove(threadId);
  }
}

class _Unused implements UserRepository, MediaRepository, ChatVaultBridge {
  @override
  final Listenable vaultSessionChanges = ValueNotifier(0);

  bool unlocked = false;
  final linked = <String, VaultPhoto>{};
  final trashed = <String>[];
  final unlinked = <String>[];
  Future<void> Function()? beforeTrash;

  @override
  bool get isUnlocked => unlocked;

  @override
  Future<VaultPhoto?> linkedAttachment(String sourceId) async =>
      linked[sourceId];

  @override
  Future<List<String>> linkedAttachmentSources(String photoId) async => linked
      .entries
      .where((entry) => entry.value.id == photoId)
      .map((entry) => entry.key)
      .toList();

  @override
  Future<void> moveAttachmentToTrash(
    VaultPhoto photo, {
    required int expiresAtMs,
  }) async {
    await beforeTrash?.call();
    trashed.add(photo.id);
  }

  @override
  Future<void> restoreAttachmentFromTrash(String photoId) async {
    trashed.remove(photoId);
  }

  @override
  Future<void> unlinkAttachment(String sourceId) async {
    unlinked.add(sourceId);
    linked.remove(sourceId);
  }

  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnimplementedError('${i.memberName} not needed');
}

ChatMessage _msg(
  String id,
  String text, {
  String sender = 'other',
  DateTime? sentAt,
  MessageReply? replyTo,
  MessageStatus? status,
}) => ChatMessage(
  messageId: id,
  threadId: 't',
  senderId: sender,
  encryptedText: text,
  sentAt: sentAt ?? DateTime.now().toUtc().subtract(const Duration(minutes: 1)),
  deletedFor: const [],
  replyTo: replyTo,
  status: status,
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
    final drafts = _Drafts();
    var locked = false;
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
            onLock: () => locked = true,
            chatDraftRepository: drafts,
            stickerPackFactory: (uid) =>
                LocalStickerPackRepository(userId: uid),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    messages.live.add([
      _msg('m1', 'hello there'),
      _msg(
        'm2',
        'reply to the original',
        sender: 'me',
        replyTo: const MessageReply(
          messageId: 'm1',
          senderId: 'other',
          encryptedPreview: 'hello there',
          localDecryptedPreview: 'hello there',
        ),
        status: MessageStatus.read,
      ),
    ]);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(MessageBubble), findsNWidgets(2));
    expect(
      tester.getSize(find.byKey(const ValueKey('bubble-m1'))).width,
      greaterThan(100),
    );
    expect(
      find.textContaining('hello there', findRichText: true),
      findsNWidgets(2),
    );
    final readTick = tester.widget<Icon>(find.byIcon(Icons.done_all_rounded));
    expect(readTick.color, isNotNull);
    expect(readTick.size, 18);

    final replyBubble = tester.widget<MessageBubble>(
      find.byKey(const ValueKey('bubble-m2')),
    );
    replyBubble.onTapQuote!.call('m1');
    await tester.pump();
    final originalBubble = find.byKey(const ValueKey('bubble-m1'));
    expect(tester.widget<MessageBubble>(originalBubble).isReplyTarget, isTrue);
    final initialFlashPhase = tester
        .widget<MessageBubble>(originalBubble)
        .replyFlashVisible;
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<MessageBubble>(originalBubble).replyFlashVisible,
      isNot(initialFlashPhase),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester.widget<MessageBubble>(originalBubble).replyFlashVisible,
      initialFlashPhase,
    );

    // Not awaited: delivery never completes, so the message stays pending.
    unawaited(cubit.sendText('my reply').then<void>((_) {}));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MessageBubble), findsNWidgets(3));
    expect(find.textContaining('my reply', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);

    final longText = List.filled(20, 'a long message line').join('\n');
    await tester.enterText(find.byType(TextField).last, longText);
    await tester.pump();
    final composerSurface = find.byKey(const ValueKey('chat-composer-surface'));
    expect(
      (tester.widget<Container>(composerSurface).decoration! as BoxDecoration)
          .borderRadius,
      BorderRadius.circular(18),
    );
    expect(tester.getSize(composerSurface).height, lessThan(200));
    expect(
      tester.getCenter(find.byTooltip('Emoji, stickers, and GIFs')).dx,
      lessThan(tester.getCenter(find.byTooltip('Attach')).dx),
    );
    await tester.tap(find.byTooltip('Attach'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Record Video'), findsOneWidget);
    expect(find.text('Notes & Lists'), findsOneWidget);
    final attachmentGridFinder = find.byKey(
      const ValueKey('attachment-options-grid'),
    );
    final attachmentGrid = tester.widget<GridView>(attachmentGridFinder);
    expect(
      (attachmentGrid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      3,
    );
    expect(attachmentGrid.padding, EdgeInsets.zero);
    expect(tester.getRect(attachmentGridFinder).left, closeTo(0, 0.5));
    expect(tester.getRect(attachmentGridFinder).right, closeTo(360, 0.5));
    expect(tester.getRect(attachmentGridFinder).height, closeTo(352, 0.5));
    expect(find.text('Checklist'), findsNothing);
    expect(find.text('Note'), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField).last, 'draft in composer');
    await tester.tap(find.byTooltip('Emoji, stickers, and GIFs'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ChatMediaPickerPanel), findsOneWidget);
    final pickerComposer = find.byType(TextField).last;
    expect(
      tester.widget<TextField>(pickerComposer).controller!.text,
      'draft in composer',
    );
    expect(
      tester.getRect(pickerComposer).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(ChatMediaPickerPanel)).top),
    );
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byType(ChatMediaPickerPanel), findsNothing);
    final composer = find.byType(TextField).last;
    expect(tester.widget<TextField>(composer).focusNode!.hasFocus, isTrue);
    await tester.enterText(composer, 'typed after picker');
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester.widget<TextField>(composer).controller!.text,
      'typed after picker',
    );
    expect(drafts.values['t'], 'cipher:typed after picker');
    expect(find.byType(ChatMediaPickerPanel), findsNothing);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(drafts.values['t'], 'cipher:typed after picker');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    await tester.tap(find.byTooltip('Lock vault'));
    expect(locked, isTrue);
    expect(drafts.values['t'], 'cipher:typed after picker');

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump();
    expect(find.text('Search this chat'), findsOneWidget);
    expect(find.text('Jump to date'), findsOneWidget);
    expect(find.text('Clear messages'), findsOneWidget);
    expect(find.text('Delete thread'), findsOneWidget);
    expect(find.text('Manage media'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(drafts.values['t'], 'cipher:typed after picker');

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
            onLock: () => locked = true,
            chatDraftRepository: drafts,
            stickerPackFactory: (uid) =>
                LocalStickerPackRepository(userId: uid),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'typed after picker',
    );
    await tester.tap(find.byIcon(Icons.send_rounded).last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(drafts.values.containsKey('t'), isFalse);
    await tester.enterText(find.byType(TextField).last, 'manual draft');
    await tester.pump(const Duration(milliseconds: 400));
    expect(drafts.values['t'], 'cipher:manual draft');
    await tester.enterText(find.byType(TextField).last, '');
    await tester.pump(const Duration(milliseconds: 400));
    expect(drafts.values.containsKey('t'), isFalse);

    await cubit.close();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
    'loading older messages preserves the viewport and jump returns to latest',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final messages = _Messages();
      final unused = _Unused();
      final drafts = _Drafts();
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
              onLock: () {},
              chatDraftRepository: drafts,
              stickerPackFactory: (uid) =>
                  LocalStickerPackRepository(userId: uid),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final newestAt = DateTime.utc(2024, 1, 2, 12);
      messages.live.add(
        List.generate(
          60,
          (index) => _msg(
            'recent-$index',
            'Recent message $index',
            sender: index == 0 ? 'me' : 'other',
            sentAt: newestAt.subtract(Duration(minutes: index)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      final olderPage = Completer<List<ChatMessage>>();
      messages.nextOlderPage = olderPage;
      for (
        var attempt = 0;
        attempt < 3 && messages.loadBeforeCalls == 0;
        attempt++
      ) {
        await tester.dragFrom(const Offset(40, 400), const Offset(0, 2500));
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(messages.loadBeforeCalls, 1);
      await tester.pump(const Duration(milliseconds: 700));

      final visibleBefore = tester
          .widgetList<MessageBubble>(find.byType(MessageBubble))
          .toList();
      expect(visibleBefore, isNotEmpty);
      final anchorMessageId = visibleBefore.first.message.messageId;
      final anchorFinder = find.byKey(ValueKey('bubble-$anchorMessageId'));
      final anchorTopBefore = tester.getTopLeft(anchorFinder).dy;

      olderPage.complete(
        List.generate(
          10,
          (index) => _msg(
            'older-$index',
            'Older message $index',
            sentAt: newestAt.subtract(Duration(minutes: 60 + index)),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byTooltip('Scroll to latest'), findsOneWidget);
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('jump-to-latest-button')),
            )
            .onPressed,
        isNotNull,
      );
      expect(anchorFinder, findsOneWidget);
      expect(
        (tester.getTopLeft(anchorFinder).dy - anchorTopBefore).abs(),
        lessThan(24),
      );

      messages.live.add([
        _msg(
          'incoming-while-reading',
          'Incoming while reading',
          sentAt: newestAt.add(const Duration(minutes: 1)),
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        (cubit.state as ActiveThreadLoaded).messages.map((m) => m.messageId),
        contains('incoming-while-reading'),
      );
      expect(anchorFinder, findsOneWidget);
      expect(
        (tester.getTopLeft(anchorFinder).dy - anchorTopBefore).abs(),
        lessThan(24),
      );
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('jump-to-latest-button')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const ValueKey('jump-to-latest-button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('bubble-incoming-while-reading')),
        findsOneWidget,
      );

      messages.live.add([
        _msg(
          'incoming-while-pinned',
          'Incoming while pinned',
          sentAt: newestAt.add(const Duration(minutes: 2)),
        ),
      ]);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('bubble-incoming-while-pinned')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FloatingActionButton>(
              find.byKey(const ValueKey('jump-to-latest-button')),
            )
            .onPressed,
        isNull,
      );

      await cubit.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'editing from the emoji drawer hides the edit header and keeps the drawer open',
    (tester) async {
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
              onLock: () {},
              chatDraftRepository: _Drafts(),
              stickerPackFactory: (uid) =>
                  LocalStickerPackRepository(userId: uid),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      messages.live.add([_msg('editable', 'before 😀', sender: 'me')]);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 500));

      tester
          .widget<MessageBubble>(find.byKey(const ValueKey('bubble-editable')))
          .onEdit!
          .call();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Edit message'), findsWidgets);

      await tester.enterText(find.byType(TextField).first, 'edited 😀');
      await tester.pump();
      await tester.tap(find.byTooltip('Emoji, stickers, and GIFs').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(ChatMediaPickerPanel), findsOneWidget);
      expect(find.text('Edit message'), findsWidgets);
      final checkButton = find.byIcon(Icons.check_rounded).last;
      await tester.tap(checkButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(messages.editedTexts, ['cipher:edited 😀']);
      expect(find.text('Edit message'), findsNothing);
      expect(find.byType(ChatMediaPickerPanel), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await cubit.close();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('can select multiple messages and delete them', (tester) async {
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
            onLock: () {},
            chatDraftRepository: _Drafts(),
            stickerPackFactory: (uid) =>
                LocalStickerPackRepository(userId: uid),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    messages.live.add([
      _msg('msg-1', 'First message', sender: 'me'),
      _msg('msg-2', 'Second message', sender: 'me'),
    ]);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('First message'), findsOneWidget);
    expect(find.text('Second message'), findsOneWidget);

    // Invoke select on first bubble
    final bubble1 = tester.widget<MessageBubble>(
      find.byKey(const ValueKey('bubble-msg-1')),
    );
    expect(bubble1.onSelect, isNotNull);
    bubble1.onSelect!.call();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Selection mode active
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byTooltip('Delete selected messages'), findsOneWidget);
    expect(find.byTooltip('Save selected media to vault'), findsNothing);
    final selectedCheck = tester.getRect(
      find.byIcon(Icons.check_circle_rounded),
    );
    final firstBubbleRect = tester.getRect(find.text('First message'));
    expect(selectedCheck.left, lessThan(40));
    expect(selectedCheck.right, lessThan(firstBubbleRect.left));
    expect(firstBubbleRect.right, greaterThan(300));

    // Tapping the message row toggles its selection indicator.
    await tester.ensureVisible(find.text('Second message'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Second message'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(2));
    expect(find.byTooltip('Save selected media to vault'), findsNothing);

    // Tap delete button
    await tester.tap(find.byTooltip('Delete selected messages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Delete 2 messages?'), findsOneWidget);
    expect(find.text('Delete for me'), findsOneWidget);
    expect(find.text('Delete for everyone'), findsOneWidget);

    // Tap "Delete for everyone"
    await tester.tap(find.text('Delete for everyone'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Verify messages were deleted for everyone
    expect(
      messages.deletedForEveryone.map((e) => e.messageId),
      unorderedEquals(['msg-1', 'msg-2']),
    );
    // Verify selection mode exited
    expect(find.text('2 selected'), findsNothing);

    messages.live.add([
      _msg(
        'video-msg',
        'Video attachment',
      ).copyWith(mediaType: MessageType.video, mediaRef: 'video-ref'),
    ]);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
    final videoBubble = tester.widget<MessageBubble>(
      find.byKey(const ValueKey('bubble-video-msg')),
    );
    videoBubble.onSelect!.call();
    await tester.pump();
    expect(find.byTooltip('Save selected media to vault'), findsOneWidget);
    expect(find.byIcon(Icons.archive_outlined), findsOneWidget);

    await cubit.close();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'deleting a linked message trashes its vault item with progress',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final messages = _Messages();
      final unused = _Unused()..unlocked = true;
      final mediaLoader = ChatMediaLoader(
        mediaRepository: unused,
        cryptoService: _Crypto(),
        accountId: 'me',
      );
      final message = _msg(
        'linked-video',
        'Video attachment',
      ).copyWith(mediaType: MessageType.video, mediaRef: 'attachment-path');
      final sourceId = 'me:t:${message.messageId}:${message.mediaRef}';
      const vaultPhoto = VaultPhoto(
        id: 'vault-linked-video',
        originalFilename: 'video.mp4',
        encryptedFilePath: 'video.enc',
        thumbnailPath: 'video-thumb.enc',
        wrappedDek: 'wrapped',
        photoNonce: 'nonce',
        thumbnailNonce: 'nonce',
        encryptionVersion: 1,
        checksumSha256: 'checksum',
        fileSize: 5,
        mimeType: 'video/mp4',
        createdTimeMs: 0,
        importedTimeMs: 0,
        modifiedTimeMs: 0,
        favorite: false,
        isTrashed: false,
      );
      unused.linked[sourceId] = vaultPhoto;
      final trashGate = Completer<void>();
      unused.beforeTrash = () => trashGate.future;
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
              mediaLoader: mediaLoader,
              vaultBridge: unused,
              onLock: () {},
              chatDraftRepository: _Drafts(),
              stickerPackFactory: (uid) =>
                  LocalStickerPackRepository(userId: uid),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      messages.live.add([message]);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 300));

      tester
          .widget<MessageBubble>(
            find.byKey(const ValueKey('bubble-linked-video')),
          )
          .onSelect!
          .call();
      await tester.pump();
      await tester.tap(find.byTooltip('Delete selected messages'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('will also be moved to Bin'), findsOneWidget);
      await tester.tap(find.text('Delete for me'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Deleting selected messages'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(messages.deletedForUser, isEmpty);

      trashGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(messages.deletedForUser.single.messageId, message.messageId);
      expect(unused.trashed, ['vault-linked-video']);
      expect(unused.unlinked, [sourceId]);
      expect(find.text('Deleting selected messages'), findsNothing);

      final singleMessage = _msg('single-linked-video', 'Single video')
          .copyWith(
            mediaType: MessageType.video,
            mediaRef: 'single-attachment-path',
          );
      final singleSourceId =
          'me:t:${singleMessage.messageId}:${singleMessage.mediaRef}';
      const singlePhoto = VaultPhoto(
        id: 'vault-single-video',
        originalFilename: 'single-video.mp4',
        encryptedFilePath: 'single-video.enc',
        thumbnailPath: 'single-video-thumb.enc',
        wrappedDek: 'wrapped',
        photoNonce: 'nonce',
        thumbnailNonce: 'nonce',
        encryptionVersion: 1,
        checksumSha256: 'single-checksum',
        fileSize: 5,
        mimeType: 'video/mp4',
        createdTimeMs: 0,
        importedTimeMs: 0,
        modifiedTimeMs: 0,
        favorite: false,
        isTrashed: false,
      );
      unused.linked[singleSourceId] = singlePhoto;
      messages.live.add([singleMessage]);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      tester
          .widget<MessageBubble>(
            find.byKey(const ValueKey('bubble-single-linked-video')),
          )
          .onDeleteForMe
          .call();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.textContaining('linked Vault item will also be moved to Bin'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        messages.deletedForUser.map((entry) => entry.messageId),
        contains('single-linked-video'),
      );
      expect(unused.trashed, contains('vault-single-video'));
      expect(unused.unlinked, contains(singleSourceId));

      await cubit.close();
      mediaLoader.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
