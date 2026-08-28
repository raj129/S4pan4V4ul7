import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../../domain/repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // Only the email scope is required to obtain a Firebase credential.
  // Requesting drive.appdata here causes Android's Credential Manager to
  // reject the entire flow (error code 16 / reauth failed) because sensitive
  // OAuth scopes cannot be pre-authorized inline in the account picker.
  static const List<String> _authScopes = ['email'];

  // Drive scope is requested lazily only when Google Drive backup is needed.
  static const List<String> _driveScopes = [
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  @override
  Future<bool> isSignedIn() async {
    return _firebaseAuth.currentUser != null;
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount googleUser = await _googleSignIn.authenticate(
        scopeHint: _authScopes,
      );

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final authorization = await googleUser.authorizationClient
          .authorizeScopes(_authScopes);

      final accessToken = authorization.accessToken;
      final idToken = googleAuth.idToken;
      if (accessToken == null && idToken == null) {
        throw const AuthException(
          'Google did not return an authentication token.',
        );
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: accessToken,
        idToken: idToken,
      );

      final UserCredential userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) {
        throw const AuthException('Firebase sign-in failed.');
      }

      return AuthResult(
        userId: user.uid,
        email: user.email ?? '',
      );
    } on AuthException {
      rethrow;
    } on PlatformException catch (e) {
      // Code 16 = SIGN_IN_CANCELLED / reauth failed from Credential Manager.
      if (e.code == 'sign_in_canceled' ||
          e.code == 'sign_in_cancelled' ||
          e.code == '16') {
        throw const AuthException(
          'Sign-in was cancelled. Please try again.',
        );
      }
      throw AuthException(
        'Google sign-in failed: ${e.message ?? e.code}',
      );
    } catch (e) {
      throw AuthException('Google sign-in failed: $e');
    }
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  @override
  Future<http.Client?> getAuthenticatedClient() async {
    final account = await _googleSignIn.attemptLightweightAuthentication();
    if (account == null) return null;

    try {
      final allScopes = [..._authScopes, ..._driveScopes];
      final authHeaders =
          await account.authorizationClient.authorizationHeaders(allScopes);
      if (authHeaders == null) return null;
      return _AuthenticatedClient(authHeaders);
    } catch (_) {
      // Drive authorization failed (e.g. user did not grant drive scope).
      // Return null so callers fall back gracefully.
      return null;
    }
  }
}

class _AuthenticatedClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _inner = http.Client();

  _AuthenticatedClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }
}
