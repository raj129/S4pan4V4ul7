import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/chat_thread.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../domain/repositories/thread_repository.dart';
import '../../../domain/repositories/user_repository.dart';
import '../../../domain/repositories/message_repository.dart';

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
  const ThreadListLoaded(this.items);
  final List<ThreadListItem> items;
  @override
  List<Object?> get props => [items];
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
    required this.myUid,
  }) : super(const ThreadListLoading());

  final ThreadRepository threadRepository;
  final UserRepository userRepository;
  final MessageRepository messageRepository;
  final MediaRepository mediaRepository;
  final String myUid;

  StreamSubscription<List<ChatThread>>? _sub;

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
        emit(ThreadListLoaded(items));
      },
      onError: (e) => emit(ThreadListError(e.toString())),
    );
  }

  Future<void> deleteThread(String threadId) async {
    try {
      await messageRepository.deleteAllMessages(threadId);
      await mediaRepository.deleteThreadMedia(threadId);
      await threadRepository.deleteThread(threadId);
    } catch (e) {
      emit(ThreadListError('Delete failed: $e'));
    }
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    return super.close();
  }
}
