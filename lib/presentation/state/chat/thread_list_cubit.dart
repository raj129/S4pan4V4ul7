import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../domain/entities/user_presence.dart';
import '../../../domain/repositories/presence_repository.dart';
import '../../../domain/repositories/thread_repository.dart';
import '../../../domain/repositories/user_repository.dart';
import '../../../domain/repositories/message_repository.dart';
import '../../../domain/repositories/message_cache_repository.dart';

// ── States ──────────────────────────────────────────────────────────────────

sealed class ThreadListState extends Equatable {
  const ThreadListState();
  @override
  List<Object?> get props => [];
}

class ThreadListLoading extends ThreadListState {
  const ThreadListLoading();
}

class ThreadListLoaded extends ThreadListState {
  const ThreadListLoaded(this.items, {this.presence = const {}});
  final List<ThreadListItem> items;

  /// Online state keyed by uid, kept alongside the items rather than inside
  /// them so a presence tick does not rebuild the whole item list identity.
  final Map<String, UserPresence> presence;

  bool isOnline(String uid) => presence[uid]?.isOnline ?? false;

  ThreadListLoaded copyWith({
    List<ThreadListItem>? items,
    Map<String, UserPresence>? presence,
  }) => ThreadListLoaded(
    items ?? this.items,
    presence: presence ?? this.presence,
  );

  @override
  List<Object?> get props => [items, presence];
}

class ThreadListError extends ThreadListState {
  const ThreadListError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

class ThreadListItem extends Equatable {
  const ThreadListItem({required this.thread, required this.otherUser});
  final ChatThread thread;
  final ChatUser otherUser;
  @override
  List<Object?> get props => [thread, otherUser];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class ThreadListCubit extends Cubit<ThreadListState> {
  ThreadListCubit({
    required this.threadRepository,
    required this.userRepository,
    required this.messageRepository,
    required this.mediaRepository,
    required this.presenceRepository,
    required this.messageCache,
    required this.myUid,
  }) : super(const ThreadListLoading());

  final ThreadRepository threadRepository;
  final UserRepository userRepository;
  final MessageRepository messageRepository;
  final MediaRepository mediaRepository;
  final PresenceRepository presenceRepository;
  final MessageCacheRepository messageCache;
  final String myUid;

  StreamSubscription<List<ChatThread>>? _sub;
  StreamSubscription<Map<String, UserPresence>>? _presenceSub;

  /// Uids currently being watched, so the presence subscription is only rebuilt
  /// when the set of conversation partners actually changes.
  List<String> _watchedUids = const [];

  /// Profiles already resolved this session, so a thread list that re-emits
  /// while offline can still render partners whose lookup now fails.
  final Map<String, ChatUser> _userCache = {};

  void startWatching() {
    _sub?.cancel();
    _sub = threadRepository.watchThreadsForUser(myUid).listen((threads) async {
      final items = <ThreadListItem>[];
      for (final t in threads) {
        final otherUid = t.otherParticipantId(myUid);
        // A lookup that throws (offline, profile never cached) must not
        // escape this async listener: that left the list loading forever.
        ChatUser? user;
        try {
          user = await userRepository.getUserById(otherUid);
        } catch (_) {
          user = null;
        }
        user ??= _userCache[otherUid];
        if (user == null) continue;
        _userCache[otherUid] = user;
        items.add(
          ThreadListItem(thread: await _maskHiddenPreview(t), otherUser: user),
        );
      }
      if (isClosed) return;
      final current = state;
      emit(
        ThreadListLoaded(
          items,
          presence: current is ThreadListLoaded ? current.presence : const {},
        ),
      );
      _watchPresenceFor(items.map((i) => i.otherUser.uid).toList());
    }, onError: (e) => emit(ThreadListError(e.toString())));
  }

  /// Blanks the preview when the last message is hidden on this device (the
  /// chat was cleared, or it predates the restore/install horizon).
  Future<ChatThread> _maskHiddenPreview(ChatThread t) async {
    try {
      final cleared = await messageCache.getClearedBefore(t.threadId);
      final horizon = await messageCache.getHistoryHorizon();
      final clearedHides =
          cleared != null && !t.lastMessageAt.isAfter(cleared);
      final horizonHides =
          horizon != null && !t.lastMessageAt.isAfter(horizon);
      if (clearedHides) return t.copyWith(lastMessage: '');
      if (!horizonHides) return t;
      // Restored history keeps its preview.
      final cached = await messageCache.load(threadId: t.threadId, limit: 1);
      return cached.isNotEmpty ? t : t.copyWith(lastMessage: '');
    } catch (_) {
      return t;
    }
  }

  void _watchPresenceFor(List<String> uids) {
    final sorted = [...uids]..sort();
    if (_listEquals(sorted, _watchedUids)) return;
    _watchedUids = sorted;
    _presenceSub?.cancel();
    if (sorted.isEmpty) return;
    _presenceSub = presenceRepository.watchMany(sorted).listen((presence) {
      final current = state;
      if (current is ThreadListLoaded) {
        emit(current.copyWith(presence: presence));
      }
    });
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Local-only "Clear chat": hides history on this device without touching
  /// Firestore or the other participant's copy (mirrors Signal/WhatsApp).
  /// Use [deleteThread] instead for a destructive, shared delete.
  Future<void> clearThread(String threadId) async {
    try {
      final now = DateTime.now().toUtc();
      await messageCache.setClearedBefore(threadId, now);
      await messageCache.clearThread(threadId);
    } catch (e) {
      emit(ThreadListError('Clear failed: $e'));
    }
  }

  Future<void> deleteThread(String threadId) async {
    try {
      await messageRepository.deleteAllMessages(threadId);
      await mediaRepository.deleteThreadMedia(threadId);
      await threadRepository.deleteThread(threadId);
      await messageCache.clearThread(threadId);
    } catch (e) {
      emit(ThreadListError('Delete failed: $e'));
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _presenceSub?.cancel();
    return super.close();
  }
}
