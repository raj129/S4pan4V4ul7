import 'dart:async';
import '../../application/media/android_chat_uploads.dart';
import '../../application/media/android_chat_local_media.dart';
import '../../application/media/chat_media_loader.dart';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_thread.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/entities/message_metadata.dart';
import '../../domain/entities/message_reply.dart';
import '../../domain/entities/user_presence.dart';
import '../../application/services/chat_search_indexer.dart';
import '../../application/media/image_compressor.dart';
import '../../application/media/video_compressor.dart';
import '../../domain/repositories/chat_search_index_repository.dart';
import '../../domain/repositories/message_cache_repository.dart';
import '../../domain/repositories/message_repository.dart';
import '../../domain/repositories/outbox_repository.dart';
import '../../domain/repositories/presence_repository.dart';
import '../../domain/repositories/thread_repository.dart';
import '../../domain/repositories/typing_repository.dart';
import '../../domain/repositories/user_repository.dart';
import '../../application/crypto/chat_crypto_service.dart';
import '../../application/media/media_send_status.dart';
import 'delegates/thread_search_delegate.dart';
import 'delegates/thread_upload_coordinator.dart';

export 'delegates/thread_upload_coordinator.dart' show OutgoingImageItem;
export '../../application/media/video_compressor.dart' show VideoQuality;

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
    this.uploadProgress = const {},
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

  /// Progress of each outgoing attachment, keyed by message id. An entry
  /// exists only while that attachment is being prepared or uploaded.
  final Map<String, MediaSendStatus> uploadProgress;

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
    Map<String, MediaSendStatus>? uploadProgress,
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
    uploadProgress: uploadProgress ?? this.uploadProgress,
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
    uploadProgress,
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

class ActiveThreadCubit extends Cubit<ActiveThreadState>
    with WidgetsBindingObserver {
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
    this.imageCompressor = const ImageCompressor(),
    this.onMediaReady,
    this.androidUploads,
    this.localMedia,
    this.mediaLoader,
    ChatSearchIndexRepository searchIndex =
        const NoopChatSearchIndexRepository(),
    Stream<List<ConnectivityResult>>? connectivityStream,
  }) : super(const ActiveThreadLoading()) {
    _searchDelegate = ThreadSearchDelegate(
      indexer: ChatSearchIndexer(
        index: searchIndex,
        cryptoService: cryptoService,
      ),
      messageCache: messageCache,
      messageRepository: messageRepository,
      myUid: myUid,
      currentThreadId: () => _currentThreadId,
      clearedBefore: () => _clearedBefore,
      horizon: () => _horizon,
      getState: () => state,
      emit: emit,
      jumpToMessage: jumpToMessage,
      decryptAll: _decryptAll,
      isClosed: () => isClosed,
      openGeneration: () => _openGeneration,
    );
    _uploadCoordinator = ThreadUploadCoordinator(
      androidUploads: androidUploads,
      localMedia: localMedia,
      mediaLoader: mediaLoader,
      mediaRepository: mediaRepository,
      cryptoService: cryptoService,
      outbox: outbox,
      messageCache: messageCache,
      imageCompressor: imageCompressor,
      onMediaReady: onMediaReady,
      myUid: myUid,
      currentThreadId: () => _currentThreadId,
      otherUser: () => _otherUser,
      isClosed: () => isClosed,
      isBufferContaining: (id) => _buffer.containsKey(id),
      getBufferMessage: (id) => _buffer[id],
      getPendingMessage: (id) => _pending[id],
      setPendingMessage: (id, msg) => _pending[id] = msg,
      removePendingMessage: (id) => _pending.remove(id),
      afterClearWatermark: _afterClearWatermark,
      setUploadStatus: _setUploadStatus,
      advanceUpload: _advanceUpload,
      emitMessages: _emitMessages,
      reportActionError: _reportActionError,
      discardMessage: discardMessage,
      deliverOutboxItem: _deliver,
      decryptAll: _decryptAll,
      showPending: _showPending,
    );
    _uploadCoordinator.initialize();
    WidgetsBinding.instance.addObserver(this);
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
    unawaited(drainOutbox());
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
  final AndroidChatUploads? androidUploads;

  /// Downscales outgoing photos and builds their previews.
  final ImageCompressor imageCompressor;

  /// Publishes locally prepared bytes under their storage path, so the
  /// sender's own attachment renders without downloading it back.
  final void Function(String storagePath, Uint8List bytes)? onMediaReady;
  final AndroidChatLocalMedia? localMedia;
  final ChatMediaLoader? mediaLoader;

  late final ThreadSearchDelegate _searchDelegate;
  late final ThreadUploadCoordinator _uploadCoordinator;

  @visibleForTesting
  ThreadSearchDelegate get searchDelegate => _searchDelegate;

  @visibleForTesting
  ThreadUploadCoordinator get uploadCoordinator => _uploadCoordinator;

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

  /// Bumped on every open so background work for a previous thread stops.
  int _openGeneration = 0;

  static const _pageSize = 30;

  static const _uuid = Uuid();
  static final Set<String> _inFlightMessageIds = {};

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
    _searchDelegate.resetForThread();
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

    List<OutboxItem> queued;
    try {
      queued = await outbox.pendingForThread(thread.threadId);
    } catch (_) {
      queued = const [];
    }
    for (final item in queued.where((item) => item.senderId == myUid)) {
      String preview;
      try {
        preview = await cryptoService.decryptMessage(
          threadId: item.threadId,
          encryptedB64: item.encryptedText,
        );
      } catch (_) {
        preview = '🔒 Encrypted message';
      }
      var message = item.toOptimisticMessage().withDecryptedText(preview);
      if (_inFlightMessageIds.contains(item.messageId)) {
        message = message.copyWith(status: MessageStatus.sending);
      }
      _pending[item.messageId] = message;
    }
    if (androidUploads != null) {
      await _uploadCoordinator.syncAndroidUploads(androidUploads!.jobs);
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
    unawaited(_searchDelegate.syncLocalHistory(thread.threadId, generation));

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
            final undelivered = visible
                .where(
                  (message) =>
                      message.senderId != myUid &&
                      !message.deliveredTo.contains(myUid),
                )
                .map((message) => message.messageId)
                .toList();
            if (undelivered.isNotEmpty) {
              _fireAndForget(
                () => messageRepository.markDelivered(
                  threadId: thread.threadId,
                  messageIds: undelivered,
                  uid: myUid,
                ),
              );
            }
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

    if (_pending.isNotEmpty) _emitMessages();

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
    if (!_inFlightMessageIds.add(item.messageId)) return;
    if (item.threadId == _currentThreadId &&
        (item.attempts > 0 || !_pending.containsKey(item.messageId))) {
      _showPending(item, decryptedPreview, status: MessageStatus.sending);
    }
    try {
      if (await _uploadCoordinator.tryRecoverAndroidOutboxItem(item)) {
        return;
      }
      final msg = await messageRepository.sendMessage(
        threadId: item.threadId,
        senderId: item.senderId,
        encryptedText: item.encryptedText,
        messageId: item.messageId,
        sentAt: item.queuedAt,
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
      if (item.threadId == _currentThreadId) {
        _pending[item.messageId] = decryptedPreview == null
            ? msg
            : msg.withDecryptedText(decryptedPreview);
        _emitMessages();
      }
    } catch (e) {
      await outbox.markFailed(item.messageId, e.toString());
      _showPending(
        item.copyWith(attempts: item.attempts + 1),
        decryptedPreview,
      );
      if (item.threadId == _currentThreadId) {
        _reportActionError('Not sent — will retry when you are back online.');
      }
    } finally {
      _inFlightMessageIds.remove(item.messageId);
    }
  }

  void _showPending(
    OutboxItem item,
    String? decryptedPreview, {
    MessageStatus? status,
  }) {
    if (item.threadId != _currentThreadId) return;
    var msg = item.toOptimisticMessage();
    if (decryptedPreview != null) {
      msg = msg.withDecryptedText(decryptedPreview);
    }
    if (status != null) msg = msg.copyWith(status: status);
    _pending[item.messageId] = msg;
    _emitMessages();
  }

  /// Retry every queued message for this account, even when its thread is not
  /// currently open.
  Future<void> drainOutbox() async {
    List<OutboxItem> queued;
    try {
      queued = await outbox.pending();
    } catch (_) {
      return;
    }
    for (final item in queued) {
      if (item.senderId != myUid) continue;
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
    if (_uploadCoordinator.isAndroidJob(messageId)) {
      await _uploadCoordinator.retryAndroidJob(messageId);
      return;
    }
    final threadId = _currentThreadId;
    if (threadId == null) return;
    final queued = await outbox.pendingForThread(threadId);
    for (final item in queued) {
      if (item.messageId == messageId) {
        if (item.mediaType != null && item.mediaRef == null) {
          _reportActionError(
            'Original file unavailable. Reattach or discard this message.',
          );
          return;
        }
        await _deliver(item);
        return;
      }
    }
  }

  /// Abandon a failed message.
  Future<void> discardMessage(String messageId) async {
    if (_uploadCoordinator.isAndroidJob(messageId)) {
      await cancelUpload(messageId);
      return;
    }
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

  /// Search the thread's whole local history for [query] and highlight the
  /// matches in place, without hiding any messages. Jumps to the newest
  /// match first.
  void setSearchQuery(String query) => _searchDelegate.setSearchQuery(query);

  void clearSearch() => _searchDelegate.clearSearch();

  /// Move to the next *older* match.
  Future<void> nextMatch() => _searchDelegate.nextMatch();

  /// Move to the next *newer* match.
  Future<void> previousMatch() => _searchDelegate.previousMatch();

  void _indexMessages(String threadId, Iterable<ChatMessage> msgs) =>
      _searchDelegate.indexMessages(threadId, msgs);

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
      if (androidUploads != null && message.mediaRef != null) {
        Future<Uint8List> source(String path) async {
          if (mediaLoader != null) {
            return mediaLoader!.fetchUncached(
              threadId: message.threadId,
              storagePath: path,
              senderId: message.senderId,
            );
          }
          if (localMedia != null) {
            throw StateError('Local attachment resolver is unavailable.');
          }
          return cryptoService.decryptMedia(
            threadId: message.threadId,
            encryptedBytes: await mediaRepository.downloadEncryptedMedia(path),
          );
        }

        final plain = await source(message.mediaRef!);
        Uint8List? thumbnail;
        try {
          final id = _uuid.v4();
          final sourceThumb = message.mediaMeta?.thumbRef;
          var meta = message.mediaMeta;
          if (sourceThumb != null) {
            thumbnail = await source(sourceThumb);
            meta = MediaMeta(
              width: meta?.width,
              height: meta?.height,
              sizeBytes: plain.length,
              thumbRef: 'chat_media/$targetThreadId/$id/thumb.enc',
            );
          } else {
            meta = MediaMeta(
              width: meta?.width,
              height: meta?.height,
              sizeBytes: plain.length,
            );
          }
          final ciphertext = await cryptoService.encryptMedia(
            threadId: targetThreadId,
            bytes: plain,
          );
          final encryptedThumbnail = thumbnail == null
              ? null
              : await cryptoService.encryptMedia(
                  threadId: targetThreadId,
                  bytes: thumbnail,
                );
          if (localMedia != null) {
            await localMedia!.put(
              uid: myUid,
              path: 'chat_media/$targetThreadId/$id/media.enc',
              direction: ChatMediaDirection.sent,
              ciphertext: ciphertext,
            );
            if (encryptedThumbnail != null) {
              await localMedia!.put(
                uid: myUid,
                path: 'chat_media/$targetThreadId/$id/thumb.enc',
                direction: ChatMediaDirection.sent,
                ciphertext: encryptedThumbnail,
              );
            }
          }
          await androidUploads!.enqueue(
            message: ChatMessage(
              messageId: id,
              threadId: targetThreadId,
              senderId: myUid,
              encryptedText: await cryptoService.encryptMessage(
                threadId: targetThreadId,
                plaintext: message.mediaPreview,
              ),
              sentAt: DateTime.now().toUtc(),
              deletedFor: const [],
              mediaType: message.mediaType,
              mediaMeta: meta,
              isForwarded: true,
            ),
            recipientUid: targetRecipientUid,
            ciphertext: ciphertext,
            thumbnail: encryptedThumbnail,
          );
        } finally {
          plain.fillRange(0, plain.length, 0);
          thumbnail?.fillRange(0, thumbnail.length, 0);
        }
        return;
      }
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
  static const maxAttachmentBytes = ThreadUploadCoordinator.maxAttachmentBytes;

  /// Storage object extension. Documents deliberately use a neutral one so the
  /// bucket listing does not reveal the file type.
  static String _storageExtension(MessageType? type) =>
      ThreadUploadCoordinator.storageExtension(type);

  /// Publishes (or clears, when [status] is null) the progress of an outgoing
  /// attachment.
  void _setUploadStatus(String messageId, MediaSendStatus? status) {
    if (isClosed) return;
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    final next = Map<String, MediaSendStatus>.from(current.uploadProgress);
    if (status == null) {
      if (next.remove(messageId) == null) return;
    } else {
      if (next[messageId] == status) return;
      next[messageId] = status;
    }
    emit(current.copyWith(uploadProgress: next));
  }

  /// Advances the bar within one phase, never backwards.
  void _advanceUpload(String messageId, MediaSendPhase phase, double progress) {
    if (isClosed) return;
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    final existing = current.uploadProgress[messageId];
    // A late callback from an earlier phase must not rewind the ring.
    if (existing != null && progress < existing.progress) return;
    _setUploadStatus(
      messageId,
      MediaSendStatus(phase: phase, progress: progress),
    );
  }

  /// Abort a send that is still being prepared or uploaded, and remove its
  /// bubble. Has no effect once delivery has started.
  Future<void> cancelUpload(String messageId) =>
      _uploadCoordinator.cancelUpload(messageId);

  Future<void> pauseUpload(String messageId) =>
      _uploadCoordinator.pauseUpload(messageId);

  Future<void> resumeUpload(String messageId) =>
      _uploadCoordinator.resumeUpload(messageId);

  /// Encrypt, upload and send an attachment.
  Future<void> sendMedia({
    required String messageId,
    required List<int> rawBytes,
    required MessageType type,
    String? filename,
    ImageQuality quality = ImageQuality.high,
    VideoQuality videoQuality = VideoQuality.high,
    bool propagateFailure = false,
    String? sourceUri,
    int sourceFlags = 0,
  }) => _uploadCoordinator.sendMedia(
    messageId: messageId,
    rawBytes: rawBytes,
    type: type,
    filename: filename,
    quality: quality,
    videoQuality: videoQuality,
    propagateFailure: propagateFailure,
    sourceUri: sourceUri,
    sourceFlags: sourceFlags,
  );

  /// Queue multiple images at once, immediately showing optimistic messages in
  /// the thread while background isolate preparation and upload proceed.
  Future<void> sendMultipleImages({
    required List<OutgoingImageItem> items,
    required ImageQuality quality,
  }) => _uploadCoordinator.sendMultipleImages(
    items: items,
    quality: quality,
  );

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
    if (isClosed) return;
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
    if (isClosed) return;
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
    if (_uploadCoordinator.isUploading(message.messageId)) {
      await cancelUpload(message.messageId);
      return;
    }
    await messageRepository.deleteMessageForUser(
      threadId: _currentThreadId!,
      messageId: message.messageId,
      uid: myUid,
    );
    await _removeLocalAttachment(message);
  }

  Future<void> deleteMessageForEveryone(ChatMessage message) async {
    if (_currentThreadId == null) return;
    if (_uploadCoordinator.isUploading(message.messageId)) {
      await cancelUpload(message.messageId);
      return;
    }
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
    await _removeLocalAttachment(message);
    await _searchDelegate.remove([message.messageId]);
  }

  Future<void> _removeLocalAttachment(ChatMessage message) =>
      _uploadCoordinator.removeLocalAttachment(message);

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
    WidgetsBinding.instance.removeObserver(this);
    _messageSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();
    _typingDebounce?.cancel();
    _searchDelegate.dispose();
    _openGeneration++;
    _openTimeoutTimer?.cancel();
    _connectivitySub?.cancel();
    await _uploadCoordinator.dispose();
    if (_currentThreadId != null) {
      await typingRepository.setTyping(
        threadId: _currentThreadId!,
        uid: myUid,
        isTyping: false,
      );
    }
    return super.close();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(drainOutbox());
    }
  }
}
