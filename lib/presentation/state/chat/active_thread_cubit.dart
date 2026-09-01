import 'dart:async';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../domain/entities/message_reply.dart';
import '../../../domain/entities/user_presence.dart';
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

class ActiveThreadLoaded extends ActiveThreadState {
  const ActiveThreadLoaded({
    required this.thread,
    required this.otherUser,
    required this.messages,
    required this.otherIsTyping,
    this.otherIsOnline = false,
    this.hasMore = true,
    this.loadingOlder = false,
    this.actionError,
    this.replyTarget,
    this.searchQuery = '',
  });
  final ChatThread thread;
  final ChatUser otherUser;
  final List<ChatMessage> messages;
  final bool otherIsTyping;

  /// Sourced from [PresenceRepository], not from [otherUser] — presence is
  /// deliberately not part of the user entity.
  final bool otherIsOnline;
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

  /// Active in-thread search term; empty means no filtering.
  final String searchQuery;

  /// The messages actually rendered.
  ///
  /// Search runs over the decrypted in-memory buffer rather than the cache,
  /// because the cache deliberately stores ciphertext only — there is nothing
  /// there for SQL to match against.
  List<ChatMessage> get visibleMessages {
    final q = searchQuery.trim().toLowerCase();
    if (q.isEmpty) return messages;
    return messages
        .where(
          (m) =>
              !m.deletedForEveryone &&
              (m.localDecryptedText ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  ActiveThreadLoaded copyWith({
    List<ChatMessage>? messages,
    bool? otherIsTyping,
    bool? otherIsOnline,
    bool? hasMore,
    bool? loadingOlder,
    String? actionError,
    bool clearActionError = false,
    ChatMessage? replyTarget,
    bool clearReplyTarget = false,
    String? searchQuery,
  }) =>
      ActiveThreadLoaded(
        thread: thread,
        otherUser: otherUser,
        messages: messages ?? this.messages,
        otherIsTyping: otherIsTyping ?? this.otherIsTyping,
        otherIsOnline: otherIsOnline ?? this.otherIsOnline,
        hasMore: hasMore ?? this.hasMore,
        loadingOlder: loadingOlder ?? this.loadingOlder,
        actionError: clearActionError ? null : (actionError ?? this.actionError),
        replyTarget:
            clearReplyTarget ? null : (replyTarget ?? this.replyTarget),
        searchQuery: searchQuery ?? this.searchQuery,
      );

  @override
  List<Object?> get props => [
        thread,
        otherUser,
        messages,
        otherIsTyping,
        otherIsOnline,
        hasMore,
        loadingOlder,
        actionError,
        replyTarget,
        searchQuery,
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
  }) : super(const ActiveThreadLoading());

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

  StreamSubscription<List<ChatMessage>>? _messageSub;
  StreamSubscription<bool>? _typingSub;
  StreamSubscription<UserPresence>? _presenceSub;
  Timer? _typingDebounce;
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

  static const _pageSize = 30;

  static const _uuid = Uuid();

  /// Locally-queued messages not yet acknowledged by Firestore, newest first.
  ///
  /// Kept separate from [_buffer] so that when the real message arrives on the
  /// stream the optimistic copy disappears without a merge conflict.
  final Map<String, ChatMessage> _pending = {};

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

    emit(const ActiveThreadLoading());

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
        _mergeIntoBuffer(await _decryptAll(cached, thread.threadId));
        _emitMessages();
      }
    } catch (_) {
      // A cold or corrupt cache must never block opening the thread.
    }

    // Mark as read.
    await threadRepository.resetUnread(
      threadId: thread.threadId,
      uid: myUid,
    );

    _messageSub?.cancel();
    _typingSub?.cancel();
    _presenceSub?.cancel();

    _messageSub = messageRepository.watchMessages(thread.threadId).listen(
      (msgs) async {
        final decrypted = await _decryptAll(msgs, thread.threadId);
        _mergeIntoBuffer(decrypted);
        _emitMessages();
        // Cache ciphertext, not the decrypted copies.
        unawaited(messageCache.save(msgs).catchError((_) {}));
      },
      onError: (e) {
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
      // The delivered message arrives on the live stream under the same id, so
      // the optimistic copy is no longer needed.
      _pending.remove(item.messageId);
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
        ? (target.mediaType == MessageType.video ? '🎥 Video' : '📷 Photo')
        : (target.localDecryptedText ?? '');
    // Long quotes are truncated: the header only ever renders two lines.
    final snippet = source.length > 160 ? '${source.substring(0, 160)}…' : source;

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
  Future<void> markVisibleAsRead() async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    final unread = _buffer.values
        .where((m) => m.senderId != myUid && !m.isReadBy(myUid))
        .map((m) => m.messageId)
        .toList();
    if (unread.isEmpty) return;
    try {
      await messageRepository.markRead(
        threadId: threadId,
        messageIds: unread,
        uid: myUid,
      );
    } catch (_) {
      // Receipts are best-effort; a failure must not disturb the UI.
    }
  }

  // ---------------------------------------------------------------------------
  // Edit
  // ---------------------------------------------------------------------------

  /// Replace the body of an already-sent message.
  Future<void> editMessage(ChatMessage message, String newText) async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    if (message.senderId != myUid) return;
    final trimmed = newText.trim();
    if (trimmed.isEmpty || trimmed == message.localDecryptedText) return;
    try {
      await messageRepository.editMessage(
        threadId: threadId,
        messageId: message.messageId,
        encryptedText: await cryptoService.encryptMessage(
          threadId: threadId,
          plaintext: trimmed,
        ),
      );
    } catch (e) {
      _reportActionError('Could not edit message: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Search
  // ---------------------------------------------------------------------------

  /// Filter the thread to messages containing [query].
  void setSearchQuery(String query) {
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    if (current.searchQuery == query) return;
    emit(current.copyWith(searchQuery: query));
  }

  void clearSearch() => setSearchQuery('');

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
        final forwardedId = '${message.messageId}_fwd_'
            '${DateTime.now().millisecondsSinceEpoch}';
        final reEncrypted = await cryptoService.encryptMedia(
          threadId: targetThreadId,
          bytes: plain,
        );
        final ext = message.mediaType == MessageType.video
            ? 'mp4.enc'
            : 'jpg.enc';
        storagePath = await mediaRepository.uploadEncryptedMedia(
          threadId: targetThreadId,
          messageId: forwardedId,
          filename: '$forwardedId.$ext',
          encryptedBytes: reEncrypted,
        );
        preview = message.mediaType == MessageType.video
            ? '🎥 Video'
            : '📷 Photo';
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

  Future<void> sendMedia({
    required String messageId,
    required List<int> rawBytes,
    required MessageType type,
  }) async {
    final threadId = _currentThreadId;
    if (threadId == null) return;
    final preview = type == MessageType.image ? '📷 Photo' : '🎥 Video';
    try {
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
        queuedAt: DateTime.now().toUtc(),
      );
      await outbox.enqueue(item);
      _showPending(item, preview);

      final encrypted = await cryptoService.encryptMedia(
        threadId: threadId,
        bytes: Uint8List.fromList(rawBytes),
      );
      final ext = type == MessageType.video ? 'mp4.enc' : 'jpg.enc';
      final storagePath = await mediaRepository.uploadEncryptedMedia(
        threadId: threadId,
        messageId: messageId,
        filename: '$messageId.$ext',
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
      _mergeIntoBuffer(decrypted);
      unawaited(messageCache.save(older).catchError((_) {}));
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
        _mergeIntoBuffer(await _decryptAll(cached, threadId));
        _emitMessages(loadingOlder: false);
      } catch (_) {
        _emitMessages(
          loadingOlder: false,
          actionError: 'Could not load older messages: $e',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Buffer
  // ---------------------------------------------------------------------------

  void _mergeIntoBuffer(List<ChatMessage> msgs) {
    for (final msg in msgs) {
      _buffer[msg.messageId] = msg;
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
    // delivered message is never shown twice.
    for (final entry in _pending.entries) {
      if (!_buffer.containsKey(entry.key)) list.add(entry.value);
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
    String? actionError,
    bool clearActionError = false,
  }) {
    if (_thread == null || _otherUser == null) return;
    final current = state;
    final messages = _sortedBuffer();
    if (current is ActiveThreadLoaded) {
      emit(current.copyWith(
        messages: messages,
        hasMore: hasMore,
        loadingOlder: loadingOlder,
        actionError: actionError,
        clearActionError: clearActionError,
      ));
    } else {
      emit(ActiveThreadLoaded(
        thread: _thread!,
        otherUser: _otherUser!,
        messages: messages,
        otherIsTyping: false,
        hasMore: hasMore ?? !_reachedStart,
        loadingOlder: loadingOlder ?? false,
        actionError: actionError,
      ));
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
      _typingDebounce = Timer(const Duration(seconds: 3), () => setTyping(false));
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
