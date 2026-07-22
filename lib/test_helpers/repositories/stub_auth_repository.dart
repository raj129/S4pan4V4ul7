import '../../domain/repositories/auth_repository.dart';

/// Stub auth repository used until Firebase is configured.
///
/// Always returns unauthenticated; calling [signInWithGoogle] throws
/// [AuthException] with a descriptive message so the UI can offer
/// "continue locally" as a fallback.
///
/// Replace this with a `FirebaseAuthRepository` once `google-services.json`
/// is added and `firebase_auth` / `google_sign_in` are in pubspec.yaml.
class StubAuthRepository implements AuthRepository {
  const StubAuthRepository();

  @override
  Future<bool> isSignedIn() async => false;

  @override
  Future<AuthResult> signInWithGoogle() async {
    throw const AuthException(
      'Google sign-in is not yet configured. '
      'Add google-services.json and wire FirebaseAuthRepository to enable it.',
    );
  }

  @override
  Future<void> signOut() async {}
}
