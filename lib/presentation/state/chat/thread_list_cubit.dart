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
  }) =>
      ThreadListLoaded(items ?? this.items, presence: presence ?? this.presence);

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

  void startWatching() {
    _sub?.cancel();
    _sub = threadRepository.watchThreadsForUser(myUid).listen(
      (threads) async {
        final items = <ThreadListItem>[];
        for (final t in threads) {
          final otherUid = t.otherParticipantId(myUid);
          final user = await userRepository.getUserById(otherUid);
          if (user != null) items.add(ThreadListItem(thread: t, otherUser: user));
        }
        final current = state;
        emit(ThreadListLoaded(
          items,
          presence: current is ThreadListLoaded ? current.presence : const {},
        ));
        _watchPresenceFor(items.map((i) => i.otherUser.uid).toList());
      },
      onError: (e) => emit(ThreadListError(e.toString())),
    );
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
