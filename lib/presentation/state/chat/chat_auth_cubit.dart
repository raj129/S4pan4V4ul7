import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../application/services/chat_auth_service.dart';
import '../../../application/services/chat_identity_service.dart';
import '../../../application/services/presence_service.dart';
import '../../../domain/entities/chat_user.dart';
import '../../../domain/repositories/auth_repository.dart';

// ── States ──────────────────────────────────────────────────────────────────

sealed class ChatAuthState extends Equatable {
  const ChatAuthState();
  @override
  List<Object?> get props => [];
}

class ChatAuthInitial extends ChatAuthState {
  const ChatAuthInitial();
}

class ChatAuthLoading extends ChatAuthState {
  const ChatAuthLoading();
}

class ChatAuthAuthenticated extends ChatAuthState {
  const ChatAuthAuthenticated(this.user, {this.identitySync});
  final ChatUser user;

  /// Outcome of restoring the portable chat identity key. Non-null values other
  /// than `restored`/`upToDate`/`created` mean past history is still locked.
  final IdentitySyncResult? identitySync;

  /// True when a key backup exists but could not be unwrapped, so previous
  /// messages will not decrypt until the correct PIN is supplied.
  bool get historyLocked =>
      identitySync == IdentitySyncResult.pinRequired ||
      identitySync == IdentitySyncResult.wrongPin;

  @override
  List<Object?> get props => [user, identitySync];
}

class ChatAuthUnauthenticated extends ChatAuthState {
  const ChatAuthUnauthenticated();
}

class ChatAuthError extends ChatAuthState {
  const ChatAuthError(this.message);
  final String message;
  @override
  List<Object?> get props => [message];
}

// ── Cubit ────────────────────────────────────────────────────────────────────

class ChatAuthCubit extends Cubit<ChatAuthState> {
  ChatAuthCubit({
    required this.authService,
    required this.presenceService,
  }) : super(const ChatAuthInitial());

  final ChatAuthService authService;
  final PresenceService presenceService;

  ChatUser? get currentUser =>
      state is ChatAuthAuthenticated ? (state as ChatAuthAuthenticated).user : null;

  Future<void> signIn() async {
    emit(const ChatAuthLoading());
    try {
      final user = await authService.ensureSignedIn(
        allowInteractiveSignIn: true,
      );
      await presenceService.activate();
      emit(
        ChatAuthAuthenticated(
          user,
          identitySync: authService.lastIdentitySync,
        ),
      );
    } catch (e) {
      final message = e is AuthException ? e.message : e.toString();
      emit(ChatAuthError(message));
    }
  }

  Future<void> signOut() async {
    final uid = authService.currentUid;
    if (uid != null) {
      await presenceService.deactivate();
      await authService.signOut(uid);
    }
    emit(const ChatAuthUnauthenticated());
  }

  Future<void> checkSession() async {
    emit(const ChatAuthLoading());
    try {
      final user = await authService.ensureSignedIn(
        allowInteractiveSignIn: false,
      );
      await presenceService.activate();
      emit(
        ChatAuthAuthenticated(
          user,
          identitySync: authService.lastIdentitySync,
        ),
      );
    } catch (_) {
      emit(const ChatAuthUnauthenticated());
    }
  }

  void markUnauthenticated() {
    emit(const ChatAuthUnauthenticated());
  }

  /// Retries unlocking chat history with an explicitly entered PIN.
  ///
  /// Returns the outcome so the caller can show "wrong PIN" inline rather than
  /// tearing down the authenticated state.
  Future<IdentitySyncResult> unlockHistory(String pin) async {
    final result = await authService.retryIdentitySync(pin);
    final current = state;
    if (current is ChatAuthAuthenticated) {
      emit(ChatAuthAuthenticated(current.user, identitySync: result));
    }
    return result;
  }
}
