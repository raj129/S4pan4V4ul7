import 'dart:async';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image/image.dart' as img;
import 'package:uuid/uuid.dart';

import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../domain/entities/message_metadata.dart';
import '../../../domain/entities/message_reply.dart';
import '../../../domain/entities/user_presence.dart';
import '../../../application/services/chat_search_indexer.dart';
import '../../../domain/repositories/chat_search_index_repository.dart';
import '../../../domain/repositories/message_cache_repository.dart';
import '../../../domain/repositories/message_repository.dart';
import '../../../domain/repositories/outbox_repository.dart';
import '../../../domain/repositories/presence_repository.dart';
import '../../../domain/repositories/thread_repository.dart';
import '../../../domain/repositories/typing_repository.dart';
import '../../../domain/repositories/user_repository.dart';
import '../../../crypto/services/chat_crypto_service.dart';

// ── States ──────────────────────────────────────────────────────────────────

sealed class ActiveThreadState extends Equatable {
  const ActiveThreadState();
  @override
  List<Object?> get props => [];
}

class ActiveThreadLoading extends ActiveThreadState {
  const ActiveThreadLoading();
}

/// A request for the timeline to scroll to [messageId] (null = the latest
/// message). [seq] makes repeated requests for the same target distinct.
class ChatScrollRequest extends Equatable {
  const ChatScrollRequest({required this.messageId, required this.seq});
  final String? messageId;
  final int seq;
  @override
  List<Object?> get props => [messageId, seq];
}

class ActiveThreadLoaded extends ActiveThreadState {
  const ActiveThreadLoaded({
    required this.thread,
    required this.otherUser,
    required this.messages,
    required this.otherIsTyping,
    this.otherIsOnline = false,
    this.isOffline = false,
    this.hasMore = true,
    this.loadingOlder = false,
    this.actionError,
    this.replyTarget,
    this.searchQuery = '',
    this.searchMatchIds = const [],
    this.currentMatchId,
    this.searchInProgress = false,
    this.isDetached = false,
    this.loadingNewer = false,
    this.newWhileDetached = 0,
    this.indexingProgress,
    this.scrollRequest,
  });
  final ChatThread thread;
  final ChatUser otherUser;
  final List<ChatMessage> messages;
  final bool otherIsTyping;

  /// Sourced from [PresenceRepository], not from [otherUser] — presence is
  /// deliberately not part of the user entity.
  final bool otherIsOnline;
  final bool isOffline;
  final bool hasMore;
  final bool loadingOlder;

  /// A transient failure (send, reaction, delete) surfaced as a banner.
  ///
  /// Held on the loaded state rather than emitted as [ActiveThreadError]:
  /// replacing the state on a failed send used to blank the entire
  /// conversation, which loses the user's scroll position and their history.
  final String? actionError;

  /// Message staged for reply, shown as a quote above the composer.
  final ChatMessage? replyTarget;

  /// Active in-thread search term; empty means no search.
  ///
  /// Search never filters the timeline: matches are highlighted in place so
  /// the surrounding conversation stays readable, as in WhatsApp/Signal.
  final String searchQuery;

  /// Ids of messages matching [searchQuery], newest first.
  final List<String> searchMatchIds;

  /// The match the user is currently looking at (one of [searchMatchIds]).
  final String? currentMatchId;

  /// True while older history is being looked up in the local database.
  final bool searchInProgress;

  /// True when [messages] is a window into older history that does not
  /// reach the latest message (after a search jump, jump-to-date or a long
  /// scroll back). Newer messages page in from the local cache.
  final bool isDetached;

  /// True while a newer page is loading into a detached window.
  final bool loadingNewer;

  /// Messages that arrived while detached, shown as a badge on the
  /// jump-to-latest button.
  final int newWhileDetached;

  /// 0..1 while older cached history is still being added to the search
  /// index; null once everything is searchable.
  final double? indexingProgress;

  /// Latest scroll request for the screen to honour.
  final ChatScrollRequest? scrollRequest;

  bool get isSearching => searchQuery.trim().isNotEmpty;

  /// Position of [currentMatchId] in [searchMatchIds], or -1.
  int get currentMatchIndex =>
      currentMatchId == null ? -1 : searchMatchIds.indexOf(currentMatchId!);

  /// The messages actually rendered: always the full timeline.
  List<ChatMessage> get visibleMessages => messages;

  ActiveThreadLoaded copyWith({
    List<ChatMessage>? messages,
    bool? otherIsTyping,
    bool? otherIsOnline,
    bool? isOffline,
    bool? hasMore,
    bool? loadingOlder,
    String? actionError,
    bool clearActionError = false,
    ChatMessage? replyTarget,
    bool clearReplyTarget = false,
    String? searchQuery,
    List<String>? searchMatchIds,
    String? currentMatchId,
    bool clearCurrentMatch = false,
    bool? searchInProgress,
    bool? isDetached,
    bool? loadingNewer,
    int? newWhileDetached,
    double? indexingProgress,
    bool clearIndexingProgress = false,
    ChatScrollRequest? scrollRequest,
  }) => ActiveThreadLoaded(
    thread: thread,
    otherUser: otherUser,
    messages: messages ?? this.messages,
    otherIsTyping: otherIsTyping ?? this.otherIsTyping,
    otherIsOnline: otherIsOnline ?? this.otherIsOnline,
    isOffline: isOffline ?? this.isOffline,
    hasMore: hasMore ?? this.hasMore,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    actionError: clearActionError ? null : (actionError ?? this.actionError),
    replyTarget: clearReplyTarget ? null : (replyTarget ?? this.replyTarget),
    searchQuery: searchQuery ?? this.searchQuery,
    searchMatchIds: searchMatchIds ?? this.searchMatchIds,
    currentMatchId: clearCurrentMatch
        ? null
        : (currentMatchId ?? this.currentMatchId),
    searchInProgress: searchInProgress ?? this.searchInProgress,
    isDetached: isDetached ?? this.isDetached,
    loadingNewer: loadingNewer ?? this.loadingNewer,
    newWhileDetached: newWhileDetached ?? this.newWhileDetached,
    indexingProgress: clearIndexingProgress
        ? null
        : (indexingProgress ?? this.indexingProgress),
    scrollRequest: scrollRequest ?? this.scrollRequest,
  );

  @override
  List<Object?> get props => [
    thread,
    otherUser,
    messages,
    otherIsTyping,
    otherIsOnline,
    isOffline,
    hasMore,
    loadingOlder,
    actionError,
    replyTarget,
    searchQuery,
    searchMatchIds,
    currentMatchId,
    searchInProgress,
    isDetached,
    loadingNewer,
    newWhileDetached,
    indexingProgress,
    scrollRequest,
  ];
}

class ActiveThreadError extends ActiveThreadState {
  const ActiveThreadError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

/// A conversation a message can be forwarded into.
class ForwardTarget extends Equatable {
  const ForwardTarget({required this.thread, required this.user});
  final ChatThread thread;
  final ChatUser user;
  @override
  List<Object?> get props => [thread, user];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class ActiveThreadCubit extends Cubit<ActiveThreadState> {
  ActiveThreadCubit({
    required this.messageRepository,
    required this.threadRepository,
    required this.userRepository,
    required this.typingRepository,
    required this.presenceRepository,
    required this.mediaRepository,
    required this.messageCache,
    required this.outbox,
    required this.cryptoService,
    required this.myUid,
    ChatSearchIndexRepository searchIndex =
        const NoopChatSearchIndexRepository(),
    Stream<List<ConnectivityResult>>? connectivityStream,
  }) : _indexer = ChatSearchIndexer(
         index: searchIndex,
         cryptoService: cryptoService,
       ),
       super(const ActiveThreadLoading()) {
    // Auto-drain the outbox the moment connectivity is restored, instead of
    // only retrying the next time the user happens to reopen the thread —
    // this is what makes queued offline messages "send automatically once
    // connectivity is restored" rather than just "send whenever revisited."
    //
    // Deliberately opt-in only (no default `Connectivity()` stream here):
    // touching that platform EventChannel requires a live Flutter binding,
    // which plain unit tests never initialize. Production wiring passes the
    // real stream explicitly (see `ChatApp`); tests simply omit it and lose
    // nothing, since `drainOutbox()` still runs on every `openThread()`.
    if (connectivityStream != null) {
      _connectivitySub = connectivityStream.listen(
        _updateConnectivity,
        onError: (_) {},
      );
    }
  }

  final MessageRepository messageRepository;
  final ThreadRepository threadRepository;
  final UserRepository userRepository;
  final TypingRepository typingRepository;
  final PresenceRepository presenceRepository;
  final MediaRepository mediaRepository;
  final MessageCacheRepository messageCache;
  final OutboxRepository outbox;
  final ChatCryptoService cryptoService;
  final String myUid;
  final ChatSearchIndexer _indexer;

  StreamSubscription<List<ChatMessage>>? _messageSub;
  StreamSubscription<bool>? _typingSub;
  StreamSubscription<UserPresence>? _presenceSub;
  Timer? _typingDebounce;

  /// Guards against the loading state persisting forever if the cache is
  /// cold and the first live snapshot never arrives (e.g. genuinely offline
  /// with no queued writes to replay). Forces an (empty) loaded state so the
  /// composer and retry affordances are still reachable.
  Timer? _openTimeoutTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _wasOffline = false;
  bool _isOffline = false;
  String? _currentThreadId;
  ChatThread? _thread;
  ChatUser? _otherUser;

  /// Every message known to this thread, newest first, keyed by id.
  ///
  /// The live `watchMessages` query only ever returns the newest page, so its
  /// snapshots must be *merged* into this buffer rather than assigned over it.
  /// Assigning was the old behaviour and silently discarded everything
  /// [loadOlderMessages] had fetched, making the history un-scrollable.
  final Map<String, ChatMessage> _buffer = {};

  /// True once [loadOlderMessages] has hit the start of the conversation.
  bool _reachedStart = false;

  /// True while [_buffer] is a window into older history rather than the
  /// live tail. Live snapshots then only refresh messages already on screen.
  bool _detached = false;

  /// The newest decrypted live snapshot, merged back in on reattach.
  List<ChatMessage> _lastLive = const [];

  /// Live messages already counted by the jump-to-latest badge.
  final Set<String> _knownWhileDetached = {};

  /// Messages kept either side of a jump target.
  static const _windowRadius = 40;

  /// Upper bound on the in-memory timeline, so scrolling through years of
  /// history never holds (or lays out) more than a few hundred bubbles.
  static const _maxBuffer = 300;

  int _scrollSeq = 0;

  /// What is indexed per message (hash of ciphertext + searchability), so
  /// repeated live snapshots do not re-hash unchanged messages.
  final Map<String, int> _indexedSig = {};

  /// Bumped on every open so background work for a previous thread stops.
  int _openGeneration = 0;

  static const _pageSize = 30;

  static const _uuid = Uuid();

  /// Locally-queued messages not yet acknowledged by Firestore, newest first.
  ///
  /// Kept separate from [_buffer] so that when the real message arrives on the
  /// stream the optimistic copy disappears without a merge conflict.
  final Map<String, ChatMessage> _pending = {};

  /// Local-only "clear chat" watermark for the open thread (null if the chat
  /// has never been cleared on this device). Messages sent at or before this
  /// instant are hidden from the buffer even though they still exist on the
  /// server / for the other participant.
  DateTime? _clearedBefore;

  /// Device-wide history horizon (see [MessageCacheRepository.getHistoryHorizon]).
  DateTime? _horizon;

  /// Set once a server page contained a hidden message: everything older is
  /// hidden too, so further history can only come from the local cache.
  bool _serverHistoryHidden = false;

  List<ChatMessage> _afterClearWatermark(List<ChatMessage> msgs) {
    final cutoff = _clearedBefore;
    if (cutoff == null) return msgs;
    return msgs.where((m) => m.sentAt.isAfter(cutoff)).toList();
  }

  /// Server messages this device may show: after the clear watermark and
  /// either after the history horizon or already present from the cache
  /// (i.e. restored from a backup).
  List<ChatMessage> _visibleFromServer(List<ChatMessage> msgs) {
    final horizon = _horizon;
    final visible = <ChatMessage>[];
    for (final m in _afterClearWatermark(msgs)) {
      if (horizon == null ||
          m.sentAt.isAfter(horizon) ||
          _buffer.containsKey(m.messageId)) {
        visible.add(m);
      } else {
        _serverHistoryHidden = true;
      }
    }
    if (visible.length < msgs.length && _clearedBefore != null) {
      _serverHistoryHidden = true;
    }
    return visible;
  }

  /// Ciphertext originals of [visible], so hidden history never reaches the
  /// cache (and therefore never reaches a backup).
  static List<ChatMessage> _originalsOf(
    List<ChatMessage> originals,
    List<ChatMessage> visible,
  ) {
    final ids = {for (final m in visible) m.messageId};
    return originals.where((m) => ids.contains(m.messageId)).toList();
  }

  // ---------------------------------------------------------------------------
  // Open thread
  // ---------------------------------------------------------------------------

  Future<void> openThread({
    required ChatThread thread,
    required ChatUser otherUser,
  }) async {
    _currentThreadId = thread.threadId;
    _thread = thread;
    _otherUser = otherUser;
    _buffer.clear();
    _pending.clear();
    _reachedStart = false;
    _serverHistoryHidden = false;
    _detached = false;
    _lastLive = const [];
    _knownWhileDetached.clear();
    _indexedSig.clear();
    _searchDebounce?.cancel();
    _searchRefresh?.cancel();
    _searchGeneration++;
    final generation = ++_openGeneration;

    emit(const ActiveThreadLoading());

    try {
      _clearedBefore = await messageCache.getClearedBefore(thread.threadId);
    } catch (_) {
      _clearedBefore = null;
    }
    try {
      _horizon = await messageCache.getHistoryHorizon();
    } catch (_) {
      _horizon = null;
    }

    // Ensure thread key is derived if not already stored.
    if (otherUser.publicKey.isNotEmpty) {
      try {
        await cryptoService.deriveAndStoreThreadKey(
          threadId: thread.threadId,
          otherPublicKeyB64: otherUser.publicKey,
        );
      } catch (_) {
        // Key already exists or derivation is pending.
      }
    }

    // Paint from the local cache before Firestore answers. Without this the
    // thread shows a spinner on every open, even for conversations whose
    // history has not changed.
    try {
      final cached = await messageCache.load(
        threadId: thread.threadId,
        limit: _pageSize,
      );
      if (cached.isNotEmpty) {
        final decrypted = _afterClearWatermark(
          await _decryptAll(cached, thread.threadId),
        );
        _mergeIntoBuffer(decrypted);
        _emitMessages();
        _indexMessages(thread.threadId, decrypted);
      }
    } catch (_) {
      // A cold or corrupt cache must never block opening the thread.
    }

    // Fill the cache with everything that arrived while the thread was
    // closed, then make the whole cached history searchable.
    unawaited(_syncLocalHistory(thread.threadId, generation));

    // Mark as read without awaiting: offline, a Firestore write only completes
    // once the server acknowledges it, and waiting here used to keep the
    // message subscription below from ever starting.
    _fireAndForget(
      () => threadRepository.resetUnread(threadId: thread.threadId, uid: myUid),
    );

    _messageSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _openTimeoutTimer?.cancel();

    // Belt-and-braces: if neither the cache nor the live stream produces a
    // result within a few seconds, stop spinning and show the (possibly
    // empty) thread instead of a permanent loading indicator.
    _openTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (state is ActiveThreadLoading) {
        _emitMessages();
      }
    });

    _messageSub = messageRepository
        .watchMessages(thread.threadId)
        .listen(
          (msgs) async {
            final decrypted = await _decryptAll(msgs, thread.threadId);
            if (thread.threadId != _currentThreadId) return;
            final visible = _visibleFromServer(decrypted);
            _lastLive = visible;
            _openTimeoutTimer?.cancel();
            if (_detached && state is ActiveThreadLoaded) {
              _applyLiveWhileDetached(visible);
            } else {
              _mergeIntoBuffer(visible);
              _emitMessages();
            }
            // Cache ciphertext, not the decrypted copies.
            unawaited(
              messageCache.save(_originalsOf(msgs, visible)).catchError((_) {}),
            );
            _indexMessages(thread.threadId, visible);
          },
          onError: (e) {
            _openTimeoutTimer?.cancel();
            // With a warm cache the conversation is still readable, so degrade to
            // a banner instead of replacing the screen with an error.
            if (_buffer.isNotEmpty) {
              _reportActionError('Offline — showing saved messages.');
            } else {
              emit(ActiveThreadError(e.toString()));
            }
          },
        );

    _typingSub = typingRepository
        .watchTyping(threadId: thread.threadId, otherUid: otherUser.uid)
        .listen((isTyping) {
          final current = state;
          if (current is ActiveThreadLoaded) {
            emit(current.copyWith(otherIsTyping: isTyping));
          }
        });

    _presenceSub = presenceRepository.watch(otherUser.uid).listen((presence) {
      final current = state;
      if (current is ActiveThreadLoaded) {
        emit(current.copyWith(otherIsOnline: presence.isOnline));
      }
    });

    // Flush anything written while offline, now that a connection is likely.
    unawaited(drainOutbox());
  }

  // ---------------------------------------------------------------------------
  // Send text message
  // ---------------------------------------------------------------------------

  Future<void> sendText(String plaintext) async {
    if (plaintext.trim().isEmpty) return;
    final threadId = _currentThreadId;
    if (threadId == null) return;
    // Captured before the await chain so a reply cannot attach itself to the
    // wrong message if the user clears the composer mid-send.
    final reply = await _buildReplyPayload(threadId);
    try {
      final encrypted = await cryptoService.encryptMessage(
        threadId: threadId,
        plaintext: plaintext.trim(),
      );
      clearReplyTarget();
      await _enqueueAndDeliver(
        OutboxItem(
          messageId: _uuid.v4(),
          threadId: threadId,
          senderId: myUid,
          encryptedText: encrypted,
          recipientUid: _otherUser!.uid,
          preview: '🔒 Message',
          replyTo: reply,
          queuedAt: DateTime.now().toUtc(),
        ),
        decryptedPreview: plaintext.trim(),
      );
      await setTyping(false);
    } catch (e) {
      // Encryption failed, so there is nothing worth queueing. Keep the
      // conversation on screen; re-opening the thread here used to blank the
      // list and lose the user's scroll position.
      _reportActionError('Send failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Outbox
  // ---------------------------------------------------------------------------

  /// Queue a message, show it immediately, then try to deliver it.
  ///
  /// Queueing happens *before* the network call so a send survives the app
  /// being killed while offline; the durable copy is the source of truth and
  /// the optimistic bubble is only a view of it.
  Future<void> _enqueueAndDeliver(
    OutboxItem item, {
    String? decryptedPreview,
  }) async {
    if (_detached) await jumpToLatest();
    await outbox.enqueue(item);
    _showPending(item, decryptedPreview);
    await _deliver(item, decryptedPreview: decryptedPreview);
  }

  Future<void> _deliver(OutboxItem item, {String? decryptedPreview}) async {
    try {
      final msg = await messageRepository.sendMessage(
        threadId: item.threadId,
        senderId: item.senderId,
        encryptedText: item.encryptedText,
        messageId: item.messageId,
        mediaRef: item.mediaRef,
        mediaType: item.mediaType,
        mediaMeta: item.mediaMeta,
        replyTo: item.replyTo,
      );
      await outbox.remove(item.messageId);
      await threadRepository.updateLastMessage(
        threadId: item.threadId,
        preview: item.preview,
        sentAt: msg.sentAt,
      );
      await threadRepository.incrementUnread(
        threadId: item.threadId,
        recipientUid: item.recipientUid,
      );
      // Keep a sent local copy until the matching Firestore snapshot arrives.
      // Removing it here could make a successful message disappear briefly
      // while the listener is still catching up.
      _pending[item.messageId] = decryptedPreview == null
          ? msg
          : msg.withDecryptedText(decryptedPreview);
      if (item.threadId == _currentThreadId) _emitMessages();
    } catch (e) {
      await outbox.markFailed(item.messageId, e.toString());
      _showPending(
        item.copyWith(attempts: item.attempts + 1),
        decryptedPreview,
      );
      _reportActionError('Not sent — will retry when you are back online.');
    }
  }

  void _showPending(OutboxItem item, String? decryptedPreview) {
    if (item.threadId != _currentThreadId) return;
    var msg = item.toOptimisticMessage();
    if (decryptedPreview != null) {
      msg = msg.withDecryptedText(decryptedPreview);
    }
    _pending[item.messageId] = msg;
    _emitMessages();
  }

  /// Retry everything still queued for this thread.
  ///
  /// Called on thread open, so a message written while offline goes out as soon
  /// as the conversation is looked at again.
  Future<void> drainOutbox() async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    List<OutboxItem> queued;
    try {
      queued = await outbox.pendingForThread(threadId);
    } catch (_) {
      return;
    }
    for (final item in queued) {
      // A queued media message whose upload never finished cannot be retried
      // from here — the plaintext bytes are gone. Surface it as failed instead
      // of silently sending a message that points at nothing.
      if (item.mediaType != null && item.mediaRef == null) {
        _showPending(item.copyWith(attempts: item.attempts + 1), null);
        continue;
      }
      await _deliver(item);
    }
  }

  /// Retry a single failed message from its bubble.
  Future<void> retryMessage(String messageId) async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    final queued = await outbox.pendingForThread(threadId);
    for (final item in queued) {
      if (item.messageId == messageId) {
        await _deliver(item);
        return;
      }
    }
  }

  /// Abandon a failed message.
  Future<void> discardMessage(String messageId) async {
    await outbox.remove(messageId);
    _pending.remove(messageId);
    _emitMessages();
  }

  // ---------------------------------------------------------------------------
  // Reply
  // ---------------------------------------------------------------------------

  /// Stage [message] as the target of the next send.
  void setReplyTarget(ChatMessage message) {
    final current = state;
    if (current is ActiveThreadLoaded) {
      emit(current.copyWith(replyTarget: message));
    }
  }

  void clearReplyTarget() {
    final current = state;
    if (current is ActiveThreadLoaded && current.replyTarget != null) {
      emit(current.copyWith(clearReplyTarget: true));
    }
  }

  /// Encrypt a short quote of the staged reply target.
  ///
  /// The preview is encrypted with the same thread key as the message body:
  /// storing it in the clear would leak the contents of every quoted message
  /// to anyone who can read the database.
  Future<MessageReply?> _buildReplyPayload(String threadId) async {
    final current = state;
    if (current is! ActiveThreadLoaded) return null;
    final target = current.replyTarget;
    if (target == null) return null;

    final source = target.isMedia
        ? target.mediaPreview
        : (target.localDecryptedText ?? '');
    // Long quotes are truncated: the header only ever renders two lines.
    final snippet = source.length > 160
        ? '${source.substring(0, 160)}…'
        : source;

    try {
      return MessageReply(
        messageId: target.messageId,
        senderId: target.senderId,
        encryptedPreview: await cryptoService.encryptMessage(
          threadId: threadId,
          plaintext: snippet,
        ),
        mediaType: target.mediaType,
      );
    } catch (_) {
      // Never block a send because the quote could not be encrypted.
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Reactions
  // ---------------------------------------------------------------------------

  /// Toggle [emoji] as this user's reaction on [message].
  ///
  /// One reaction per user, like WhatsApp: tapping the same emoji again clears
  /// it, and a different emoji replaces the previous one.
  Future<void> toggleReaction(ChatMessage message, String emoji) async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    final existing = message.reactions[myUid];
    final next = existing == emoji ? null : emoji;
    try {
      await messageRepository.setReaction(
        threadId: threadId,
        messageId: message.messageId,
        uid: myUid,
        emoji: next,
      );
    } catch (e) {
      _reportActionError('Could not react: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Read receipts
  // ---------------------------------------------------------------------------

  /// Mark every visible incoming message as read.
  ///
  /// Only messages from the other user and not already marked are sent, so a
  /// scroll through a long thread does not rewrite documents needlessly.
  bool _markingVisibleAsRead = false;

  Future<void> markVisibleAsRead() async {
    final threadId = _currentThreadId;
    final current = state;
    if (threadId == null || current is! ActiveThreadLoaded) return;
    final unread = current.visibleMessages
        .where((m) => m.senderId != myUid && !m.isReadBy(myUid))
        .map((m) => m.messageId)
        .toList();
    if (unread.isEmpty || _markingVisibleAsRead) return;
    _markingVisibleAsRead = true;
    try {
      // The writes are queued locally and not awaited: offline they would
      // never be acknowledged and this guard would stay set for good.
      _fireAndForget(
        () => messageRepository.markRead(
          threadId: threadId,
          messageIds: unread,
          uid: myUid,
        ),
      );
      _fireAndForget(
        () => threadRepository.resetUnread(threadId: threadId, uid: myUid),
      );
      final latest = state;
      if (latest is! ActiveThreadLoaded) return;
      final nextMessages = latest.messages
          .map(
            (m) => unread.contains(m.messageId)
                ? m.copyWith(readBy: [...m.readBy, myUid])
                : m,
          )
          .toList();
      emit(latest.copyWith(messages: nextMessages));
    } finally {
      _markingVisibleAsRead = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Edit
  // ---------------------------------------------------------------------------

  /// Replace the body of an already-sent message.
  bool canEditMessage(ChatMessage message) {
    if (message.senderId != myUid ||
        message.isMedia ||
        message.deletedForEveryone) {
      return false;
    }
    final now = DateTime.now().toUtc();
    final sentAt = message.sentAt.toUtc();
    final hasBeenRead = message.readBy.any((uid) => uid != myUid);
    if (!hasBeenRead) return true;
    return now.difference(sentAt) <= const Duration(minutes: 30);
  }

  Future<void> editMessage(ChatMessage message, String newText) async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    if (!canEditMessage(message)) {
      _reportActionError('This message can no longer be edited.');
      return;
    }
    final trimmed = newText.trim();
    if (trimmed.isEmpty || trimmed == message.localDecryptedText) return;
    try {
      final encrypted = await cryptoService.encryptMessage(
        threadId: threadId,
        plaintext: trimmed,
      );
      await messageRepository.editMessage(
        threadId: threadId,
        messageId: message.messageId,
        encryptedText: encrypted,
      );
      final edited = _buffer[message.messageId]?.copyWith(
        encryptedText: encrypted,
        localDecryptedText: trimmed,
        editedAt: DateTime.now().toUtc(),
      );
      if (edited != null) {
        _buffer[message.messageId] = edited;
        _indexMessages(threadId, [edited]);
      }
      final current = state;
      if (current is ActiveThreadLoaded) {
        emit(
          current.copyWith(
            messages: current.messages
                .map(
                  (m) => m.messageId == message.messageId
                      ? m.copyWith(
                          encryptedText: encrypted,
                          localDecryptedText: trimmed,
                          editedAt: DateTime.now().toUtc(),
                        )
                      : m,
                )
                .toList(),
          ),
        );
      }
    } catch (e) {
      _reportActionError('Could not edit message: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  static const _searchDebounceDuration = Duration(milliseconds: 250);

  /// Placeholder bodies that must never count as a match.
  static const _unsearchableTexts = {
    '🚫 Message deleted',
    '🔒 Encrypted message',
  };

  Timer? _searchDebounce;

  /// Re-runs the active query after new messages are indexed.
  Timer? _searchRefresh;

  /// Bumped per query so a slow lookup cannot apply results for stale input.
  int _searchGeneration = 0;

  /// Search the thread's whole local history for [query] and highlight the
  /// matches in place, without hiding any messages. Jumps to the newest
  /// match first.
  ///
  /// The lookup runs against the keyed local index, so it is a single
  /// indexed query however many years of messages the thread holds.
  void setSearchQuery(String query) {
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    if (current.searchQuery == query) return;
    _searchDebounce?.cancel();
    _searchRefresh?.cancel();
    final generation = ++_searchGeneration;
    final trimmed = query.trim();
    emit(
      current.copyWith(
        searchQuery: query,
        searchMatchIds: const [],
        clearCurrentMatch: true,
        searchInProgress: trimmed.isNotEmpty,
      ),
    );
    if (trimmed.isEmpty) return;
    _searchDebounce = Timer(
      _searchDebounceDuration,
      () => _runSearch(trimmed, generation, jump: true),
    );
  }

  void clearSearch() => setSearchQuery('');

  /// Move to the next *older* match.
  Future<void> nextMatch() => _stepMatch(1);

  /// Move to the next *newer* match.
  Future<void> previousMatch() => _stepMatch(-1);

  Future<void> _stepMatch(int delta) async {
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    final ids = current.searchMatchIds;
    if (ids.isEmpty) return;
    final index = (current.currentMatchIndex + delta).clamp(0, ids.length - 1);
    if (ids[index] == current.currentMatchId) return;
    emit(current.copyWith(currentMatchId: ids[index]));
    await jumpToMessage(ids[index]);
  }

  Future<void> _runSearch(
    String query,
    int generation, {
    required bool jump,
  }) async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    List<String> ids;
    try {
      final hits = await _indexer.search(threadId, query);
      final cutoff = _clearedBefore;
      ids = [
        for (final h in hits)
          if (cutoff == null || h.sentAt.isAfter(cutoff)) h.messageId,
      ];
    } catch (_) {
      ids = const [];
    }
    if (generation != _searchGeneration || threadId != _currentThreadId) {
      return;
    }
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    final keep = current.currentMatchId;
    final String? currentId = keep != null && ids.contains(keep)
        ? keep
        : (ids.isEmpty ? null : ids.first);
    emit(
      current.copyWith(
        searchMatchIds: ids,
        currentMatchId: currentId,
        clearCurrentMatch: currentId == null,
        searchInProgress: false,
      ),
    );
    if (jump && currentId != null) await jumpToMessage(currentId);
  }

  /// Refresh the result list (without moving) once more history is indexed.
  void _scheduleSearchRefresh() {
    final current = state;
    if (current is! ActiveThreadLoaded || !current.isSearching) return;
    _searchRefresh?.cancel();
    final generation = _searchGeneration;
    final query = current.searchQuery.trim();
    _searchRefresh = Timer(const Duration(milliseconds: 400), () {
      final latest = state;
      if (generation != _searchGeneration ||
          latest is! ActiveThreadLoaded ||
          latest.searchInProgress) {
        return;
      }
      unawaited(
        _runSearch(query, generation, jump: latest.currentMatchId == null),
      );
    });
  }

  // ---------------------------------------------------------------------------
  // Local search index
  // ---------------------------------------------------------------------------

  /// The text a message contributes to search, or null if it has none.
  String? _searchableText(ChatMessage m) {
    if (m.isMedia || m.deletedForEveryone || m.isDeletedFor(myUid)) {
      return null;
    }
    final text = m.localDecryptedText;
    if (text == null || text.isEmpty || _unsearchableTexts.contains(text)) {
      return null;
    }
    return text;
  }

  /// Index decrypted messages that changed since they were last indexed.
  void _indexMessages(String threadId, Iterable<ChatMessage> msgs) {
    final inputs = <ChatIndexInput>[];
    for (final m in msgs) {
      final text = _searchableText(m);
      final sig = Object.hash(m.encryptedText, text == null);
      if (_indexedSig[m.messageId] == sig) continue;
      _indexedSig[m.messageId] = sig;
      inputs.add((messageId: m.messageId, sentAt: m.sentAt, text: text));
    }
    if (inputs.isEmpty) return;
    unawaited(
      _indexer
          .indexTexts(threadId, inputs)
          .then((_) {
            if (threadId == _currentThreadId) _scheduleSearchRefresh();
          })
          .catchError((Object _) {
            for (final i in inputs) {
              _indexedSig.remove(i.messageId);
            }
          }),
    );
  }

  /// Catch the cache up with the server, then index any cached history that
  /// is not yet searchable (e.g. restored from a backup, or cached before the
  /// index existed).
  Future<void> _syncLocalHistory(String threadId, int generation) async {
    bool stale() => generation != _openGeneration || isClosed;
    await _catchUpCache(threadId, stale);
    if (stale()) return;
    await _backfillIndex(threadId, stale);
  }

  static const _catchUpPage = 100;

  /// Save every server message newer than the newest cached one, so local
  /// search covers the whole conversation and not only what was scrolled.
  Future<void> _catchUpCache(String threadId, bool Function() stale) async {
    DateTime? cursor;
    try {
      cursor = (await messageCache.timeBounds(threadId))?.$2;
    } catch (_) {
      return;
    }
    // A cold cache has no gap to fill; live snapshots seed it.
    if (cursor == null) return;
    final horizon = _horizon;
    if (horizon != null && horizon.isAfter(cursor)) cursor = horizon;
    final cutoff = _clearedBefore;
    if (cutoff != null && cutoff.isAfter(cursor)) cursor = cutoff;

    while (!stale()) {
      final List<ChatMessage> page;
      try {
        page = await messageRepository.loadAfter(
          threadId: threadId,
          after: cursor!,
          limit: _catchUpPage,
        );
      } catch (_) {
        return; // Offline: the next open retries.
      }
      if (page.isEmpty || stale()) return;
      try {
        await messageCache.save(page);
        _indexMessages(threadId, await _decryptAll(page, threadId));
      } catch (_) {
        return;
      }
      final newest = page
          .map((m) => m.sentAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (page.length < _catchUpPage || !newest.isAfter(cursor)) return;
      cursor = newest;
    }
  }

  static const _backfillPage = 200;

  Future<void> _backfillIndex(String threadId, bool Function() stale) async {
    int total;
    try {
      total = await _indexer.index.countUnindexed(threadId);
    } catch (_) {
      return;
    }
    if (total == 0) return;
    var done = 0;
    var previousFirst = '';
    try {
      while (!stale()) {
        final batch = await _indexer.index.unindexed(
          threadId,
          limit: _backfillPage,
        );
        // Guard against a row that can never be indexed looping forever.
        if (batch.isEmpty || batch.first.messageId == previousFirst) break;
        previousFirst = batch.first.messageId;
        final decrypted = await _decryptAll(batch, threadId);
        await _indexer.indexTexts(threadId, [
          for (final m in decrypted)
            (
              messageId: m.messageId,
              sentAt: m.sentAt,
              text: _searchableText(m),
            ),
        ]);
        for (final m in decrypted) {
          _indexedSig[m.messageId] = Object.hash(
            m.encryptedText,
            _searchableText(m) == null,
          );
        }
        done += batch.length;
        final current = state;
        if (stale() || current is! ActiveThreadLoaded) break;
        emit(current.copyWith(indexingProgress: (done / total).clamp(0, 1)));
        _scheduleSearchRefresh();
        if (batch.length < _backfillPage) break;
      }
    } catch (_) {
      // Unindexed rows are picked up again on the next open.
    }
    final current = state;
    if (!stale() && current is ActiveThreadLoaded) {
      emit(current.copyWith(clearIndexingProgress: true));
      _scheduleSearchRefresh();
    }
  }

  // ---------------------------------------------------------------------------
  // Timeline window (jump to message / date / position, latest)
  // ---------------------------------------------------------------------------

  void _requestScroll(String? messageId) {
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    emit(
      current.copyWith(
        scrollRequest: ChatScrollRequest(
          messageId: messageId,
          seq: ++_scrollSeq,
        ),
      ),
    );
  }

  /// Bring [messageId] into the timeline and scroll to it, loading the
  /// surrounding conversation from the local cache if it is not in memory.
  ///
  /// Returns false if the message is not available locally.
  Future<bool> jumpToMessage(String messageId) async {
    final threadId = _currentThreadId;
    if (threadId == null || state is! ActiveThreadLoaded) return false;
    if (_buffer.containsKey(messageId) || _pending.containsKey(messageId)) {
      _requestScroll(messageId);
      return true;
    }
    try {
      final target = await messageCache.loadById(messageId);
      if (target == null || target.threadId != threadId) return false;
      final older = await messageCache.load(
        threadId: threadId,
        limit: _windowRadius,
        before: target.sentAt,
      );
      final newer = await messageCache.loadFrom(
        threadId: threadId,
        from: target.sentAt,
        limit: _windowRadius + 1,
      );
      final decrypted = _afterClearWatermark(
        await _decryptAll([...older, ...newer], threadId),
      );
      if (threadId != _currentThreadId) return false;
      final reachesLatest = await _reachesLatest(
        threadId,
        newer,
        _windowRadius + 1,
      );
      _replaceWindow(decrypted, reachesLatest: reachesLatest);
      _reachedStart = false;
      _emitMessages(hasMore: true, loadingOlder: false, loadingNewer: false);
      _requestScroll(messageId);
      _indexMessages(threadId, decrypted);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// True if [page] (oldest first, fetched with [limit]) ends at the newest
  /// cached message.
  Future<bool> _reachesLatest(
    String threadId,
    List<ChatMessage> page,
    int limit,
  ) async {
    if (page.length < limit) return true;
    final bounds = await messageCache.timeBounds(threadId);
    return bounds == null || !page.last.sentAt.isBefore(bounds.$2);
  }

  /// Scroll to the first message on or after [day] (or the last one before
  /// it if nothing was sent that day or later).
  Future<bool> jumpToDate(DateTime day) async {
    final threadId = _currentThreadId;
    if (threadId == null) return false;
    try {
      final from = DateTime(day.year, day.month, day.day).toUtc();
      final after = await messageCache.loadFrom(
        threadId: threadId,
        from: from,
        limit: 1,
      );
      final target = after.isNotEmpty
          ? after.first
          : (await messageCache.load(
              threadId: threadId,
              limit: 1,
              before: from,
            )).firstOrNull;
      if (target == null) return false;
      return jumpToMessage(target.messageId);
    } catch (_) {
      return false;
    }
  }

  /// Jump to a relative position in the cached history: 0 = the first
  /// message, 1 = the latest. Backs the draggable scrollbar.
  Future<void> jumpToFraction(double fraction) async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    try {
      final total = await messageCache.count(threadId);
      if (total == 0) return;
      final offset = (fraction.clamp(0.0, 1.0) * (total - 1)).round();
      if (offset >= total - _pageSize) {
        await jumpToLatest();
        return;
      }
      final target = await messageCache.loadAtOffset(threadId, offset);
      if (target != null) await jumpToMessage(target.messageId);
    } catch (_) {}
  }

  /// Where [message] sits in the cached history, 0 (first) .. 1 (latest),
  /// for positioning the scrollbar thumb.
  Future<double?> positionOf(ChatMessage message) async {
    final threadId = _currentThreadId;
    if (threadId == null) return null;
    try {
      final total = await messageCache.count(threadId);
      if (total <= 1) return 1;
      final older = await messageCache.count(threadId, before: message.sentAt);
      return (older / (total - 1)).clamp(0.0, 1.0);
    } catch (_) {
      return null;
    }
  }

  /// Send time of the message at [fraction] of the cached history, for the
  /// scrollbar's date bubble while dragging.
  Future<DateTime?> dateAtFraction(double fraction) async {
    final threadId = _currentThreadId;
    if (threadId == null) return null;
    try {
      final total = await messageCache.count(threadId);
      if (total == 0) return null;
      final offset = (fraction.clamp(0.0, 1.0) * (total - 1)).round();
      return (await messageCache.loadAtOffset(threadId, offset))?.sentAt;
    } catch (_) {
      return null;
    }
  }

  /// The date range of the cached history, for the jump-to-date picker.
  Future<(DateTime, DateTime)?> historyBounds() async {
    final threadId = _currentThreadId;
    if (threadId == null) return null;
    try {
      return await messageCache.timeBounds(threadId);
    } catch (_) {
      return null;
    }
  }

  /// Leave a detached window and return to the live conversation.
  Future<void> jumpToLatest() async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    if (_detached) {
      _buffer.clear();
      try {
        final cached = await messageCache.load(
          threadId: threadId,
          limit: _pageSize,
        );
        _mergeIntoBuffer(
          _afterClearWatermark(await _decryptAll(cached, threadId)),
        );
      } catch (_) {}
      _mergeIntoBuffer(_lastLive);
      _detached = false;
      _knownWhileDetached.clear();
      _reachedStart = false;
      _emitMessages(
        hasMore: true,
        loadingOlder: false,
        loadingNewer: false,
        newWhileDetached: 0,
      );
    }
    _requestScroll(null);
  }

  /// Page newer messages into a detached window from the local cache,
  /// reattaching to the live conversation once the latest is reached.
  Future<void> loadNewerMessages() async {
    final current = state;
    final threadId = _currentThreadId;
    if (!_detached || threadId == null) return;
    if (current is! ActiveThreadLoaded || current.loadingNewer) return;
    if (_buffer.isEmpty) return;
    emit(current.copyWith(loadingNewer: true));
    try {
      final newest = _sortedBuffer().first.sentAt;
      final page = await messageCache.loadFrom(
        threadId: threadId,
        from: newest,
        limit: _pageSize + 1,
      );
      final fresh = page.where((m) => !_buffer.containsKey(m.messageId));
      final decrypted = _afterClearWatermark(
        await _decryptAll(fresh.toList(), threadId),
      );
      if (threadId != _currentThreadId) return;
      _mergeIntoBuffer(decrypted);
      _indexMessages(threadId, decrypted);
      if (await _reachesLatest(threadId, page, _pageSize + 1)) {
        // Caught up: resume live updates without moving the viewport.
        _mergeIntoBuffer(_lastLive);
        _detached = false;
        _knownWhileDetached.clear();
        _trimOldest();
        _emitMessages(loadingNewer: false, newWhileDetached: 0);
        return;
      }
      _trimOldest();
      _emitMessages(loadingNewer: false);
    } catch (_) {
      _emitMessages(loadingNewer: false);
    }
  }

  /// Replace the timeline with [window], detaching from live updates unless
  /// it already reaches the latest message.
  void _replaceWindow(List<ChatMessage> window, {required bool reachesLatest}) {
    _buffer.clear();
    _mergeIntoBuffer(window);
    if (reachesLatest) {
      _mergeIntoBuffer(_lastLive);
      _detached = false;
      _knownWhileDetached.clear();
    } else {
      _detach();
    }
  }

  void _detach() {
    if (_detached) return;
    _detached = true;
    _knownWhileDetached
      ..clear()
      ..addAll(_lastLive.map((m) => m.messageId));
  }

  /// While detached, refresh messages already on screen (reactions, edits,
  /// deletions) and count genuinely new arrivals for the badge.
  void _applyLiveWhileDetached(List<ChatMessage> visible) {
    var arrived = 0;
    for (final m in visible) {
      _pending.remove(m.messageId);
      if (_buffer.containsKey(m.messageId)) {
        _buffer[m.messageId] = m;
      } else if (_knownWhileDetached.add(m.messageId) && m.senderId != myUid) {
        arrived++;
      }
    }
    final current = state;
    _emitMessages(
      newWhileDetached: current is ActiveThreadLoaded
          ? current.newWhileDetached + arrived
          : arrived,
    );
  }

  /// Keep the buffer bounded after paging newer: drop the oldest messages.
  void _trimOldest() {
    if (_buffer.length <= _maxBuffer) return;
    final sorted = _sortedBuffer();
    for (final m in sorted.skip(_maxBuffer)) {
      _buffer.remove(m.messageId);
    }
    _reachedStart = false;
  }

  /// Keep the buffer bounded after paging older: drop the newest messages,
  /// which detaches the timeline from the live tail.
  void _trimNewest() {
    if (_buffer.length <= _maxBuffer) return;
    final sorted = _sortedBuffer();
    for (final m in sorted.take(sorted.length - _maxBuffer)) {
      _buffer.remove(m.messageId);
    }
    _detach();
  }

  /// Other conversations this message can be forwarded into.
  Future<List<ForwardTarget>> loadForwardTargets() async {
    final threads = await threadRepository.watchThreadsForUser(myUid).first;
    final targets = <ForwardTarget>[];
    for (final thread in threads) {
      if (thread.threadId == _currentThreadId) continue;
      final otherUid = thread.otherParticipantId(myUid);
      final user = await userRepository.getUserById(otherUid);
      if (user != null) targets.add(ForwardTarget(thread: thread, user: user));
    }
    return targets;
  }

  // ---------------------------------------------------------------------------
  // Forward
  // ---------------------------------------------------------------------------

  /// Re-send [message] into another conversation.
  ///
  /// Every thread has its own key, so a forward is a genuine re-encryption
  /// rather than a copy of the stored ciphertext: the payload is decrypted with
  /// this thread's key and encrypted again with the target's. Media is
  /// re-uploaded for the same reason — the target's participants cannot decrypt
  /// an object encrypted for this thread.
  Future<void> forwardMessage(
    ChatMessage message, {
    required String targetThreadId,
    required String targetRecipientUid,
  }) async {
    final sourceThreadId = _currentThreadId;
    if (sourceThreadId == null) return;
    if (message.deletedForEveryone) return;

    try {
      String preview;
      String? storagePath;

      if (message.isMedia && message.mediaRef != null) {
        final encrypted = await mediaRepository.downloadEncryptedMedia(
          message.mediaRef!,
        );
        final plain = await cryptoService.decryptMedia(
          threadId: sourceThreadId,
          encryptedBytes: encrypted,
        );
        final forwardedId =
            '${message.messageId}_fwd_'
            '${DateTime.now().millisecondsSinceEpoch}';
        final reEncrypted = await cryptoService.encryptMedia(
          threadId: targetThreadId,
          bytes: plain,
        );
        storagePath = await mediaRepository.uploadEncryptedMedia(
          threadId: targetThreadId,
          messageId: forwardedId,
          filename: '$forwardedId.${_storageExtension(message.mediaType)}',
          encryptedBytes: reEncrypted,
        );
        preview = message.mediaPreview;
      } else {
        final text = message.localDecryptedText;
        if (text == null || text.isEmpty) {
          _reportActionError('Cannot forward a message that is still locked.');
          return;
        }
        preview = text;
      }

      final sent = await messageRepository.sendMessage(
        threadId: targetThreadId,
        senderId: myUid,
        encryptedText: await cryptoService.encryptMessage(
          threadId: targetThreadId,
          plaintext: preview,
        ),
        mediaRef: storagePath,
        mediaType: storagePath == null ? null : message.mediaType,
        mediaMeta: storagePath == null ? null : message.mediaMeta,
        isForwarded: true,
      );
      await threadRepository.updateLastMessage(
        threadId: targetThreadId,
        preview: preview,
        sentAt: sent.sentAt,
      );
      await threadRepository.incrementUnread(
        threadId: targetThreadId,
        recipientUid: targetRecipientUid,
      );
    } catch (e) {
      _reportActionError('Forward failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Send media
  // ---------------------------------------------------------------------------

  /// Largest attachment accepted, kept just under the 64 MB Storage rule so
  /// the AES-GCM nonce and tag never push an upload over the limit.
  static const maxAttachmentBytes = 64 * 1024 * 1024 - 1024;

  /// Storage object extension. Documents deliberately use a neutral one so the
  /// bucket listing does not reveal the file type.
  static String _storageExtension(MessageType? type) => switch (type) {
    MessageType.video => 'mp4.enc',
    MessageType.file => 'bin.enc',
    _ => 'jpg.enc',
  };

  /// Clear-text layout hints for an attachment. Best effort: an unreadable
  /// header only costs the placeholder its exact aspect ratio.
  static MediaMeta _buildMediaMeta(MessageType type, Uint8List bytes) {
    int? width;
    int? height;
    if (type == MessageType.image) {
      try {
        final info = img.findDecoderForData(bytes)?.startDecode(bytes);
        width = info?.width;
        height = info?.height;
      } catch (_) {}
    }
    return MediaMeta(width: width, height: height, sizeBytes: bytes.length);
  }

  /// Encrypt, upload and send an attachment.
  ///
  /// For [MessageType.file], [filename] is required: it becomes the encrypted
  /// message body, so the recipient sees the name but the server never does.
  Future<void> sendMedia({
    required String messageId,
    required List<int> rawBytes,
    required MessageType type,
    String? filename,
  }) async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    if (rawBytes.isEmpty) {
      _reportActionError('That file is empty.');
      return;
    }
    if (rawBytes.length > maxAttachmentBytes) {
      _reportActionError('Attachments must be smaller than 64 MB.');
      return;
    }
    final preview = ChatMessage.mediaPreviewFor(type, filename: filename);
    try {
      final bytes = rawBytes is Uint8List
          ? rawBytes
          : Uint8List.fromList(rawBytes);
      final encryptedText = await cryptoService.encryptMessage(
        threadId: threadId,
        plaintext: preview,
      );
      // Queued before the upload so the bubble appears immediately, but with no
      // mediaRef yet: an entry without one is not deliverable and drainOutbox
      // deliberately refuses to send it.
      var item = OutboxItem(
        messageId: messageId,
        threadId: threadId,
        senderId: myUid,
        encryptedText: encryptedText,
        recipientUid: _otherUser!.uid,
        preview: preview,
        mediaType: type,
        mediaMeta: _buildMediaMeta(type, bytes),
        queuedAt: DateTime.now().toUtc(),
      );
      await outbox.enqueue(item);
      _showPending(item, preview);

      final encrypted = await cryptoService.encryptMedia(
        threadId: threadId,
        bytes: bytes,
      );
      final storagePath = await mediaRepository.uploadEncryptedMedia(
        threadId: threadId,
        messageId: messageId,
        filename: '$messageId.${_storageExtension(type)}',
        encryptedBytes: encrypted,
      );
      // Recorded so a retry reuses the upload instead of repeating it.
      item = item.copyWith(mediaRef: storagePath);
      await outbox.enqueue(item);
      await _deliver(item, decryptedPreview: preview);
    } catch (e) {
      await outbox.markFailed(messageId, e.toString());
      _reportActionError('Media send failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Pagination
  // ---------------------------------------------------------------------------

  Future<void> loadOlderMessages() async {
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    if (current.loadingOlder || !current.hasMore || _reachedStart) return;
    if (_buffer.isEmpty) return;

    final threadId = _currentThreadId;
    if (threadId == null) return;

    emit(current.copyWith(loadingOlder: true));

    // The buffer is newest-first, so the cursor is the tail.
    final oldest = _sortedBuffer().last.sentAt;
    if (_serverHistoryHidden) {
      // Older server history is hidden on this device; only restored or
      // previously cached messages can extend the scroll.
      await _loadOlderFromCache(threadId, oldest);
      return;
    }
    try {
      final older = await messageRepository.loadBefore(
        threadId: threadId,
        before: oldest,
        limit: _pageSize,
      );
      if (older.isEmpty) {
        _reachedStart = true;
        _emitMessages(hasMore: false, loadingOlder: false);
        return;
      }
      final decrypted = await _decryptAll(older, threadId);
      final visible = _visibleFromServer(decrypted);
      _mergeIntoBuffer(visible);
      _trimNewest();
      unawaited(
        messageCache.save(_originalsOf(older, visible)).catchError((_) {}),
      );
      _indexMessages(threadId, visible);
      if (_serverHistoryHidden) {
        await _loadOlderFromCache(threadId, oldest);
        return;
      }
      // A short page means the query ran out of documents, not that the page
      // size happened to divide evenly.
      _reachedStart = older.length < _pageSize;
      _emitMessages(hasMore: !_reachedStart, loadingOlder: false);
    } catch (e) {
      // Offline: serve the older page from the cache instead of dead-ending
      // the scroll.
      try {
        final cached = await messageCache.load(
          threadId: threadId,
          limit: _pageSize,
          before: oldest,
        );
        if (cached.isEmpty) {
          _emitMessages(
            loadingOlder: false,
            actionError: 'Could not load older messages: $e',
          );
          return;
        }
        _mergeIntoBuffer(
          _afterClearWatermark(await _decryptAll(cached, threadId)),
        );
        _trimNewest();
        _emitMessages(loadingOlder: false);
      } catch (_) {
        _emitMessages(
          loadingOlder: false,
          actionError: 'Could not load older messages: $e',
        );
      }
    }
  }

  Future<void> _loadOlderFromCache(String threadId, DateTime before) async {
    try {
      final cached = await messageCache.load(
        threadId: threadId,
        limit: _pageSize,
        before: before,
      );
      _mergeIntoBuffer(
        _afterClearWatermark(await _decryptAll(cached, threadId)),
      );
      _trimNewest();
      _reachedStart = cached.length < _pageSize;
      _emitMessages(hasMore: !_reachedStart, loadingOlder: false);
    } catch (e) {
      _emitMessages(
        loadingOlder: false,
        actionError: 'Could not load older messages: $e',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Buffer
  // ---------------------------------------------------------------------------

  void _mergeIntoBuffer(List<ChatMessage> msgs) {
    for (final msg in msgs) {
      _buffer[msg.messageId] = msg;
      _pending.remove(msg.messageId);
    }
  }

  /// Buffer contents as a newest-first list.
  ///
  /// Ties are broken by id so the order is stable when two messages share a
  /// millisecond, which otherwise makes list items jump between rebuilds.
  List<ChatMessage> _sortedBuffer() {
    final list = _buffer.values.toList();
    // Queued messages that Firestore has not acknowledged yet. A pending entry
    // is dropped as soon as the real one lands under the same id, so a
    // delivered message is never shown twice. They belong at the live tail,
    // so a detached window into older history does not show them.
    if (!_detached) {
      for (final entry in _pending.entries) {
        if (!_buffer.containsKey(entry.key)) list.add(entry.value);
      }
    }
    list.sort((a, b) {
      final byTime = b.sentAt.compareTo(a.sentAt);
      return byTime != 0 ? byTime : b.messageId.compareTo(a.messageId);
    });
    return list;
  }

  /// Emit the buffer, preserving whichever ancillary state is already loaded.
  void _emitMessages({
    bool? hasMore,
    bool? loadingOlder,
    bool? loadingNewer,
    int? newWhileDetached,
    String? actionError,
    bool clearActionError = false,
  }) {
    if (_thread == null || _otherUser == null) return;
    final current = state;
    final messages = _sortedBuffer();
    if (current is ActiveThreadLoaded) {
      emit(
        current.copyWith(
          messages: messages,
          hasMore: hasMore,
          loadingOlder: loadingOlder,
          loadingNewer: loadingNewer,
          isDetached: _detached,
          newWhileDetached: newWhileDetached,
          actionError: actionError,
          clearActionError: clearActionError,
        ),
      );
    } else {
      emit(
        ActiveThreadLoaded(
          thread: _thread!,
          otherUser: _otherUser!,
          messages: messages,
          otherIsTyping: false,
          hasMore: hasMore ?? !_reachedStart,
          loadingOlder: loadingOlder ?? false,
          actionError: actionError,
          isOffline: _isOffline,
          isDetached: _detached,
        ),
      );
    }
  }

  /// Report a failed action without discarding the conversation.
  void _reportActionError(String message) {
    final current = state;
    if (current is ActiveThreadLoaded) {
      emit(current.copyWith(actionError: message));
    } else {
      emit(ActiveThreadError(message));
    }
  }

  /// Dismiss the action-error banner.
  void clearActionError() {
    final current = state;
    if (current is ActiveThreadLoaded && current.actionError != null) {
      emit(current.copyWith(clearActionError: true));
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    final isOffline =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    final wasOffline = _wasOffline;
    _wasOffline = isOffline;
    _isOffline = isOffline;

    final current = state;
    if (current is ActiveThreadLoaded && current.isOffline != isOffline) {
      emit(current.copyWith(isOffline: isOffline));
    }
    if (wasOffline && !isOffline) {
      unawaited(drainOutbox());
    }
  }

  /// Queues a server write without waiting for it. Offline, Firestore only
  /// completes writes once the server acknowledges them, so awaiting one on a
  /// UI path would hang; failures (sync or async) are deliberately dropped.
  void _fireAndForget(Future<void> Function() write) {
    unawaited(Future.sync(write).catchError((_) {}));
  }

  // ---------------------------------------------------------------------------
  // Typing indicator
  // ---------------------------------------------------------------------------

  Future<void> setTyping(bool isTyping) async {
    if (_currentThreadId == null) return;
    await typingRepository.setTyping(
      threadId: _currentThreadId!,
      uid: myUid,
      isTyping: isTyping,
    );
  }

  void onTextChanged(String text) {
    _typingDebounce?.cancel();
    if (text.isEmpty) {
      setTyping(false);
    } else {
      setTyping(true);
      _typingDebounce = Timer(
        const Duration(seconds: 3),
        () => setTyping(false),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Delete
  // ---------------------------------------------------------------------------

  Future<void> deleteMessageForMe(ChatMessage message) async {
    if (_currentThreadId == null) return;
    await messageRepository.deleteMessageForUser(
      threadId: _currentThreadId!,
      messageId: message.messageId,
      uid: myUid,
    );
  }

  Future<void> deleteMessageForEveryone(ChatMessage message) async {
    if (_currentThreadId == null) return;
    if (message.mediaRef != null) {
      await mediaRepository.deleteMedia(message.mediaRef!);
    }
    await messageRepository.deleteMessageForEveryone(
      threadId: _currentThreadId!,
      messageId: message.messageId,
    );
    // Drop the cached ciphertext too, otherwise the deleted body would still
    // be recoverable from local storage.
    await messageCache.remove(message.messageId);
    await _indexer.remove([message.messageId]).catchError((_) {});
    _indexedSig.remove(message.messageId);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Future<List<ChatMessage>> _decryptAll(
    List<ChatMessage> msgs,
    String threadId,
  ) async {
    final result = <ChatMessage>[];
    for (final msg in msgs) {
      if (msg.isDeletedFor(myUid)) {
        result.add(msg.withDecryptedText('🚫 Message deleted'));
        continue;
      }
      ChatMessage decrypted;
      try {
        final plain = await cryptoService.decryptMessage(
          threadId: threadId,
          encryptedB64: msg.encryptedText,
        );
        decrypted = msg.withDecryptedText(plain);
      } catch (_) {
        decrypted = msg.withDecryptedText('🔒 Encrypted message');
      }
      result.add(await _decryptReply(decrypted, threadId));
    }
    return result;
  }

  /// Decrypt the quoted preview carried by a reply.
  Future<ChatMessage> _decryptReply(ChatMessage msg, String threadId) async {
    final reply = msg.replyTo;
    if (reply == null || reply.encryptedPreview.isEmpty) return msg;
    try {
      final plain = await cryptoService.decryptMessage(
        threadId: threadId,
        encryptedB64: reply.encryptedPreview,
      );
      return msg.copyWith(replyTo: reply.withDecryptedPreview(plain));
    } catch (_) {
      return msg.copyWith(
        replyTo: reply.withDecryptedPreview('🔒 Encrypted message'),
      );
    }
  }

  @override
  Future<void> close() async {
    _messageSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _typingDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchRefresh?.cancel();
    _openGeneration++;
    _openTimeoutTimer?.cancel();
    _connectivitySub?.cancel();
    if (_currentThreadId != null) {
      await typingRepository.setTyping(
        threadId: _currentThreadId!,
        uid: myUid,
        isTyping: false,
      );
    }
    return super.close();
  }
}
