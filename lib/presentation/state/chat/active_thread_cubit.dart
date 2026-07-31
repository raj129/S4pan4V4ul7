import 'dart:async';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../domain/repositories/message_repository.dart';
import '../../../domain/repositories/thread_repository.dart';
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
    this.hasMore = true,
  });
  final ChatThread thread;
  final ChatUser otherUser;
  final List<ChatMessage> messages;
  final bool otherIsTyping;
  final bool hasMore;

  ActiveThreadLoaded copyWith({
    List<ChatMessage>? messages,
    bool? otherIsTyping,
    bool? hasMore,
  }) =>
      ActiveThreadLoaded(
        thread: thread,
        otherUser: otherUser,
        messages: messages ?? this.messages,
        otherIsTyping: otherIsTyping ?? this.otherIsTyping,
        hasMore: hasMore ?? this.hasMore,
      );

  @override
  List<Object?> get props => [thread, otherUser, messages, otherIsTyping, hasMore];
}

class ActiveThreadError extends ActiveThreadState {
  const ActiveThreadError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class ActiveThreadCubit extends Cubit<ActiveThreadState> {
  ActiveThreadCubit({
    required this.messageRepository,
    required this.threadRepository,
    required this.userRepository,
    required this.mediaRepository,
    required this.cryptoService,
    required this.myUid,
  }) : super(const ActiveThreadLoading());

  final MessageRepository messageRepository;
  final ThreadRepository threadRepository;
  final UserRepository userRepository;
  final MediaRepository mediaRepository;
  final ChatCryptoService cryptoService;
  final String myUid;

  StreamSubscription<List<ChatMessage>>? _messageSub;
  StreamSubscription<bool>? _typingSub;
  Timer? _typingDebounce;
  String? _currentThreadId;
  ChatThread? _thread;
  ChatUser? _otherUser;

  static const _pageSize = 30;

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

    // Mark as read.
    await threadRepository.resetUnread(
      threadId: thread.threadId,
      uid: myUid,
    );

    _messageSub?.cancel();
    _typingSub?.cancel();

    _messageSub = messageRepository.watchMessages(thread.threadId).listen(
      (msgs) async {
        final decrypted = await _decryptAll(msgs, thread.threadId);
        final current = state;
        if (current is ActiveThreadLoaded) {
          emit(current.copyWith(messages: decrypted));
        } else {
          emit(ActiveThreadLoaded(
            thread: _thread!,
            otherUser: _otherUser!,
            messages: decrypted,
            otherIsTyping: false,
          ));
        }
      },
      onError: (e) => emit(ActiveThreadError(e.toString())),
    );

    _typingSub = threadRepository
        .watchTyping(threadId: thread.threadId, otherUid: otherUser.uid)
        .listen((isTyping) {
      final current = state;
      if (current is ActiveThreadLoaded) {
        emit(current.copyWith(otherIsTyping: isTyping));
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Send text message
  // ---------------------------------------------------------------------------

  Future<void> sendText(String plaintext) async {
    if (plaintext.trim().isEmpty) return;
    final threadId = _currentThreadId;
    if (threadId == null) return;
    try {
      final encrypted = await cryptoService.encryptMessage(
        threadId: threadId,
        plaintext: plaintext.trim(),
      );
      final msg = await messageRepository.sendMessage(
        threadId: threadId,
        senderId: myUid,
        encryptedText: encrypted,
      );
      await threadRepository.updateLastMessage(
        threadId: threadId,
        preview: '🔒 Message',
        sentAt: msg.sentAt,
      );
      await threadRepository.incrementUnread(
        threadId: threadId,
        recipientUid: _otherUser!.uid,
      );
      // Clear typing indicator.
      await setTyping(false);
    } catch (e) {
      // Bubble to UI via state; don't crash the cubit.
      emit(ActiveThreadError('Send failed: $e'));
      // Re-open thread to recover state.
      if (_thread != null && _otherUser != null) {
        await openThread(thread: _thread!, otherUser: _otherUser!);
      }
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
    try {
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
      final msg = await messageRepository.sendMessage(
        threadId: threadId,
        senderId: myUid,
        encryptedText: await cryptoService.encryptMessage(
          threadId: threadId,
          plaintext: type == MessageType.image ? '📷 Photo' : '🎥 Video',
        ),
        mediaRef: storagePath,
        mediaType: type,
      );
      final preview = type == MessageType.image ? '📷 Photo' : '🎥 Video';
      await threadRepository.updateLastMessage(
        threadId: threadId,
        preview: preview,
        sentAt: msg.sentAt,
      );
      await threadRepository.incrementUnread(
        threadId: threadId,
        recipientUid: _otherUser!.uid,
      );
    } catch (e) {
      emit(ActiveThreadError('Media send failed: $e'));
    }
  }

  // ---------------------------------------------------------------------------
  // Pagination
  // ---------------------------------------------------------------------------

  Future<void> loadOlderMessages() async {
    final current = state;
    if (current is! ActiveThreadLoaded) return;
    if (current.messages.isEmpty) return;
    final oldest = current.messages.last.sentAt;
    final older = await messageRepository.loadBefore(
      threadId: _currentThreadId!,
      before: oldest,
      limit: _pageSize,
    );
    if (older.isEmpty) {
      emit(current.copyWith(hasMore: false));
      return;
    }
    final decrypted = await _decryptAll(older, _currentThreadId!);
    emit(current.copyWith(
      messages: [...current.messages, ...decrypted],
      hasMore: older.length == _pageSize,
    ));
  }

  // ---------------------------------------------------------------------------
  // Typing indicator
  // ---------------------------------------------------------------------------

  Future<void> setTyping(bool isTyping) async {
    if (_currentThreadId == null) return;
    await threadRepository.setTyping(
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
      try {
        final plain = await cryptoService.decryptMessage(
          threadId: threadId,
          encryptedB64: msg.encryptedText,
        );
        result.add(msg.withDecryptedText(plain));
      } catch (_) {
        result.add(msg.withDecryptedText('🔒 Encrypted message'));
      }
    }
    return result;
  }

  @override
  Future<void> close() async {
    _messageSub?.cancel();
    _typingSub?.cancel();
    _typingDebounce?.cancel();
    if (_currentThreadId != null) {
      await threadRepository.setTyping(
        threadId: _currentThreadId!,
        uid: myUid,
        isTyping: false,
      );
    }
    return super.close();
  }
}
