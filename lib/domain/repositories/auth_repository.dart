import 'package:http/http.dart' as http;

/// Authentication result from Google sign-in.
class AuthResult {
  const AuthResult({required this.userId, required this.email});
  final String userId;
  final String email;
}

/// Manages optional Google sign-in for backup/sync.
///
/// Security rule: this repository NEVER handles vault keys.
/// It only manages identity/session tokens.
abstract class AuthRepository {
  /// Whether a Google session is currently active.
  Future<bool> isSignedIn();

  /// Sign in with Google. Returns [AuthResult] on success.
  /// Throws [AuthException] on failure.
  Future<AuthResult> signInWithGoogle();

  /// Sign out and revoke the current Google session.
  Future<void> signOut();

  /// Returns an authenticated HTTP client for Google APIs.
  Future<http.Client?> getAuthenticatedClient();
}

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => 'AuthException: $message';
}
