import 'package:firebase_auth/firebase_auth.dart';

import '../../crypto/services/chat_crypto_service.dart';
import '../../domain/entities/chat_user.dart';
import '../../domain/repositories/auth_repository.dart';
import '../../domain/repositories/user_repository.dart';

/// Orchestrates Google Sign-In → Firestore profile upsert → ECDH key init.
class ChatAuthService {
  ChatAuthService({
    required this.authRepository,
    required this.userRepository,
    required this.cryptoService,
  });

  final AuthRepository authRepository;
  final UserRepository userRepository;
  final ChatCryptoService cryptoService;

  /// Sign in with Google and ensure the Firestore user profile exists.
  /// Returns the resolved [ChatUser].
  Future<ChatUser> signIn() async {
    final result = await authRepository.signInWithGoogle();
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser == null) throw const AuthException('Firebase user null after sign-in.');

    // Ensure the ECDH key pair exists on this device.
    final publicKey = await cryptoService.getOrCreatePublicKey();

    // Upsert the Firestore profile (merge so existing data is preserved).
    final now = DateTime.now().toUtc();
    final user = ChatUser(
      uid: firebaseUser.uid,
      email: (firebaseUser.email ?? result.email).toLowerCase().trim(),
      displayName: firebaseUser.displayName ?? result.email,
      photoUrl: firebaseUser.photoURL,
      publicKey: publicKey,
      isOnline: true,
      lastSeen: now,
      createdAt: now,
    );
    await userRepository.upsertProfile(user);

    // Bring presence online.
    await userRepository.updatePresence(
      uid: user.uid,
      isOnline: true,
      lastSeen: now,
    );

    return user;
  }

  /// Mark user offline and sign out.
  Future<void> signOut(String uid) async {
    await userRepository.updatePresence(
      uid: uid,
      isOnline: false,
      lastSeen: DateTime.now().toUtc(),
    );
    await authRepository.signOut();
  }

  /// Returns the currently signed-in Firebase UID, or null.
  String? get currentUid => FirebaseAuth.instance.currentUser?.uid;

  /// Returns true if a Firebase session is active.
  bool get isSignedIn => FirebaseAuth.instance.currentUser != null;
}
