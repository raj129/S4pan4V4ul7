import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/chat_user.dart';
import '../../../domain/repositories/user_repository.dart';
import '../../../domain/repositories/thread_repository.dart';
import '../../../domain/entities/chat_thread.dart';

// ── States ──────────────────────────────────────────────────────────────────

sealed class UserLookupState extends Equatable {
  const UserLookupState();
  @override
  List<Object?> get props => [];
}

class UserLookupIdle extends UserLookupState {
  const UserLookupIdle();
}

class UserLookupLoading extends UserLookupState {
  const UserLookupLoading();
}

class UserLookupFound extends UserLookupState {
  const UserLookupFound({required this.user, required this.thread});
  final ChatUser user;
  final ChatThread thread;
  @override
  List<Object?> get props => [user, thread];
}

class UserLookupNotFound extends UserLookupState {
  const UserLookupNotFound(this.email);
  final String email;
  @override
  List<Object?> get props => [email];
}

class UserLookupError extends UserLookupState {
  const UserLookupError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class UserLookupCubit extends Cubit<UserLookupState> {
  UserLookupCubit({
    required this.userRepository,
    required this.threadRepository,
    required this.myUid,
  }) : super(const UserLookupIdle());

  final UserRepository userRepository;
  final ThreadRepository threadRepository;
  final String myUid;

  Future<void> lookupByEmail(String email) async {
    emit(const UserLookupLoading());
    try {
      final target = await userRepository.getUserByEmail(email.trim().toLowerCase());
      if (target == null) {
        emit(UserLookupNotFound(email.trim()));
        return;
      }
      if (target.uid == myUid) {
        emit(const UserLookupError('You cannot start a chat with yourself.'));
        return;
      }
      final thread = await threadRepository.createOrGetThread(
        myUid: myUid,
        otherUid: target.uid,
      );
      emit(UserLookupFound(user: target, thread: thread));
    } catch (e) {
      emit(UserLookupError(e.toString()));
    }
  }

  void reset() => emit(const UserLookupIdle());
}
