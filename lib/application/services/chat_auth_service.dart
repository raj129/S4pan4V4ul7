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

  /// Ensure a chat user is available.
  ///
  /// If Firebase already has a signed-in user, reuse it and avoid an additional
  /// interactive Google sign-in prompt.
  Future<ChatUser> ensureSignedIn({required bool allowInteractiveSignIn}) async {
    var firebaseUser = FirebaseAuth.instance.currentUser;
    AuthResult? result;

    if (firebaseUser == null) {
      if (!allowInteractiveSignIn) {
        throw const AuthException('Chat sign-in required.');
      }
      result = await authRepository.signInWithGoogle();
      firebaseUser = FirebaseAuth.instance.currentUser;
    }
    if (firebaseUser == null) {
      throw const AuthException('Firebase user null after sign-in.');
    }

    final resolvedEmail = (firebaseUser.email ?? result?.email ?? '')
        .toLowerCase()
        .trim();
    if (resolvedEmail.isEmpty) {
      throw const AuthException('Google account email is unavailable.');
    }

    // Reconcile this device's identity key with the wrapped backup in
    // Firestore. On a reinstall or a second device this is what makes existing
    // history readable again, so it must happen before any thread is opened.
    lastIdentitySync = await identityService.sync(
      uid: firebaseUser.uid,
      pin: readPin(),
    );

    final publicKey = await cryptoService.getOrCreatePublicKey();

    // Upsert the Firestore profile (merge so existing data is preserved).
    final now = DateTime.now().toUtc();
    final user = ChatUser(
      uid: firebaseUser.uid,
      email: resolvedEmail,
      displayName: firebaseUser.displayName ?? resolvedEmail,
      photoUrl: firebaseUser.photoURL,
      publicKey: publicKey,
      createdAt: now,
    );
    await userRepository.upsertProfile(user);

    // Bring presence online. PresenceService owns the lifecycle from here.
    await presenceRepository.setOnline(user.uid);

    return user;
  }

  /// Mark user offline and sign out.
  Future<void> signOut(String uid) async {
    await presenceRepository.setOffline(uid);
    await authRepository.signOut();
  }

  /// Returns the currently signed-in Firebase UID, or null.
  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// Returns true if a Firebase session is active.
  bool get isSignedIn => FirebaseAuth.instance.currentUser != null;

  /// Retries the identity restore with an explicitly supplied PIN.
  ///
  /// Used when [ensureSignedIn] reported [IdentitySyncResult.pinRequired] or
  /// [IdentitySyncResult.wrongPin] and the user has now entered their PIN.
  Future<IdentitySyncResult> retryIdentitySync(String pin) async {
    final uid = currentUid;
    if (uid == null) return IdentitySyncResult.pinRequired;
    final result = await identityService.sync(uid: uid, pin: pin);
    lastIdentitySync = result;
    if (result == IdentitySyncResult.restored) {
      // The restored identity key replaces the one published at sign-in.
      await userRepository.updatePublicKey(
        uid: uid,
        publicKeyBase64: await cryptoService.getOrCreatePublicKey(),
      );
    }
    return result;
  }
}
