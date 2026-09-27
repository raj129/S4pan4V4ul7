import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
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
    Stream<List<ConnectivityResult>>? connectivityStream,
  }) : super(const ChatAuthInitial()) {
    // Opt-in for the same reason as ActiveThreadCubit: the real stream needs a
    // live platform binding that plain unit tests do not have.
    _connectivitySub = connectivityStream?.listen((results) {
      final online =
          results.any((r) => r != ConnectivityResult.none) &&
          results.isNotEmpty;
      if (online && _needsServerSync) unawaited(_syncWithServer());
    }, onError: (_) {});
  }

  final ChatAuthService authService;
  final PresenceService presenceService;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  /// Set when the background reconciliation could not reach the server, so it
  /// is retried once the device comes back online.
  bool _needsServerSync = false;
  bool _syncInFlight = false;

  ChatUser? get currentUser => state is ChatAuthAuthenticated
      ? (state as ChatAuthAuthenticated).user
      : null;

  Future<void> signIn() async {
    emit(const ChatAuthLoading());
    try {
      final user = await authService.ensureSignedIn(
        allowInteractiveSignIn: true,
      );
      _activatePresence();
      emit(
        ChatAuthAuthenticated(user, identitySync: authService.lastIdentitySync),
      );
    } catch (e) {
      final message = e is AuthException ? e.message : e.toString();
      emit(ChatAuthError(message));
    }
  }

  Future<void> signOut() async {
    final uid = authService.currentUid;
    if (uid != null) {
      _deactivatePresence();
      await authService.signOut(uid);
    }
    emit(const ChatAuthUnauthenticated());
  }

  /// Resume the existing chat session.
  ///
  /// A returning user is authenticated straight from local state so chat opens
  /// offline; the server reconciliation (identity backup, profile, presence)
  /// runs afterwards and never holds the UI on a spinner.
  Future<void> checkSession() async {
    emit(const ChatAuthLoading());
    try {
      final local = await authService.restoreLocalSession();
      if (local != null) {
        emit(ChatAuthAuthenticated(local));
        unawaited(_syncWithServer());
        return;
      }
      final user = await authService.ensureSignedIn(
        allowInteractiveSignIn: false,
      );
      _activatePresence();
      emit(
        ChatAuthAuthenticated(user, identitySync: authService.lastIdentitySync),
      );
    } catch (_) {
      emit(const ChatAuthUnauthenticated());
    }
  }

  Future<void> _syncWithServer() async {
    final current = state;
    if (current is! ChatAuthAuthenticated || _syncInFlight) return;
    _syncInFlight = true;
    try {
      final result = await authService.syncWithServer(current.user);
      _needsServerSync = false;
      final latest = state;
      if (!isClosed && latest is ChatAuthAuthenticated) {
        emit(ChatAuthAuthenticated(latest.user, identitySync: result));
      }
    } catch (_) {
      _needsServerSync = true;
    } finally {
      _syncInFlight = false;
    }
  }

  void _activatePresence() =>
      unawaited(Future.sync(presenceService.activate).catchError((_) {}));

  void _deactivatePresence() =>
      unawaited(Future.sync(presenceService.deactivate).catchError((_) {}));

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

  @override
  Future<void> close() async {
    await _connectivitySub?.cancel();
    return super.close();
  }
}
