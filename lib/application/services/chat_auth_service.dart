import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../crypto/services/chat_crypto_service.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/presence_repository.dart';
import '../../domain/repositories/user_repository.dart';
import 'chat_identity_service.dart';

/// Orchestrates Google Sign-In → Firestore profile upsert → ECDH key init.
class ChatAuthService {
  ChatAuthService({
    required this.authRepository,
    required this.userRepository,
    required this.presenceRepository,
    required this.cryptoService,
    required this.identityService,
    required this.readPin,
  });

  final AuthRepository authRepository;
  final UserRepository userRepository;
  final PresenceRepository presenceRepository;
  final ChatCryptoService cryptoService;
  final ChatIdentityService identityService;

  /// Supplies the current vault PIN, or null when the vault is locked.
  ///
  /// A callback rather than a value because sign-in can happen at any point in
  /// the session, and the PIN must never be captured for longer than the call.
  final String? Function() readPin;

  /// Result of the most recent identity reconciliation, so the UI can warn
  /// when history could not be unlocked.
  IdentitySyncResult? lastIdentitySync;

  /// Upper bound for the server round-trips done while signing in.
  ///
  /// Firestore reads fall back to the cache when offline, but a write's Future
  /// only completes once the server acknowledges it, so without a bound an
  /// offline device would wait here indefinitely.
  static const networkTimeout = Duration(seconds: 15);

  /// Ensure a chat user is available.
  ///
  /// If Firebase already has a signed-in user, reuse it and avoid an additional
  /// interactive Google sign-in prompt.
  Future<ChatUser> ensureSignedIn({
    required bool allowInteractiveSignIn,
  }) async {
    var firebaseUser = FirebaseAuth.instance.currentUser;
    AuthResult? result;

    if (firebaseUser == null) {
      if (!allowInteractiveSignIn) {
        throw const AuthException('Chat sign-in required.');
      }
      try {
        result = await authRepository.signInWithGoogle().timeout(
          const Duration(minutes: 2),
        );
      } on TimeoutException {
        throw const AuthException(
          'Sign-in timed out. Check your internet connection and try again.',
        );
      }
      firebaseUser = FirebaseAuth.instance.currentUser;
    }
    if (firebaseUser == null) {
      throw const AuthException('Firebase user null after sign-in.');
    }

    final resolvedEmail = _resolveEmail(firebaseUser, fallback: result?.email);

    // Reconcile this device's identity key with the wrapped backup in
    // Firestore. On a reinstall or a second device this is what makes existing
    // history readable again, so it must happen before any thread is opened.
    try {
      lastIdentitySync = await identityService
          .sync(uid: firebaseUser.uid, pin: readPin())
          .timeout(networkTimeout);
    } on TimeoutException {
      throw const AuthException(
        'Could not reach the server. Check your internet connection.',
      );
    }

    final user = _buildUser(
      firebaseUser,
      email: resolvedEmail,
      publicKey: await cryptoService.getOrCreatePublicKey(),
    );
    _publishProfileAndPresence(user);
    return user;
  }

  /// Restore the signed-in chat user without touching the network.
  ///
  /// Firebase persists the auth session and the identity key lives in secure
  /// storage, so a returning user can open chat offline. Returns null when a
  /// server round-trip is unavoidable: nobody is signed in, or this device has
  /// no identity key yet. Creating a key here instead would orphan existing
  /// history that a restore from the Firestore backup could have unlocked.
  Future<ChatUser?> restoreLocalSession() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) return null;
    if (!await cryptoService.hasIdentityKey()) return null;
    final email = (firebaseUser.email ?? '').toLowerCase().trim();
    if (email.isEmpty) return null;
    return _buildUser(
      firebaseUser,
      email: email,
      publicKey: await cryptoService.getOrCreatePublicKey(),
    );
  }

  /// Reconcile a locally restored session with Firestore.
  ///
  /// Throws on timeout or network failure; callers run this in the background
  /// and retry once connectivity returns.
  Future<IdentitySyncResult> syncWithServer(ChatUser user) async {
    final result = await identityService
        .sync(uid: user.uid, pin: readPin())
        .timeout(networkTimeout);
    lastIdentitySync = result;
    _publishProfileAndPresence(
      user.copyWith(publicKey: await cryptoService.getOrCreatePublicKey()),
    );
    return result;
  }

  String _resolveEmail(User firebaseUser, {String? fallback}) {
    final email = (firebaseUser.email ?? fallback ?? '').toLowerCase().trim();
    if (email.isEmpty) {
      throw const AuthException('Google account email is unavailable.');
    }
    return email;
  }

  ChatUser _buildUser(
    User firebaseUser, {
    required String email,
    required String publicKey,
  }) => ChatUser(
    uid: firebaseUser.uid,
    email: email,
    displayName: firebaseUser.displayName ?? email,
    photoUrl: firebaseUser.photoURL,
    publicKey: publicKey,
    createdAt: DateTime.now().toUtc(),
  );

  /// Queue the profile upsert and bring presence online.
  ///
  /// Not awaited: Firestore applies the writes locally at once and uploads them
  /// when a connection is available, so waiting for the acknowledgement would
  /// only block the UI while offline.
  void _publishProfileAndPresence(ChatUser user) {
    unawaited(userRepository.upsertProfile(user).catchError((_) {}));
    unawaited(presenceRepository.setOnline(user.uid).catchError((_) {}));
  }

  /// Mark user offline and sign out.
  Future<void> signOut(String uid) async {
    await presenceRepository.setOffline(uid);
    await authRepository.signOut();
  }

  /// Returns the currently signed-in Firebase UID, or null.
  String? get currentUid {
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if a Firebase session is active.
  bool get isSignedIn {
    try {
      return FirebaseAuth.instance.currentUser != null;
    } catch (_) {
      return false;
    }
  }

  /// Retries the identity restore with an explicitly supplied PIN.
  ///
  /// Used when [ensureSignedIn] reported [IdentitySyncResult.pinRequired] or
  /// [IdentitySyncResult.wrongPin] and the user has now entered their PIN.
  Future<IdentitySyncResult> retryIdentitySync(String pin) async {
    final uid = currentUid;
    if (uid == null) return IdentitySyncResult.pinRequired;
    final result = await identityService
        .sync(uid: uid, pin: pin)
        .timeout(networkTimeout);
    lastIdentitySync = result;
    if (result == IdentitySyncResult.restored) {
      // The restored identity key replaces the one published at sign-in.
      final publicKey = await cryptoService.getOrCreatePublicKey();
      unawaited(
        userRepository
            .updatePublicKey(uid: uid, publicKeyBase64: publicKey)
            .catchError((_) {}),
      );
    }
    return result;
  }
}
