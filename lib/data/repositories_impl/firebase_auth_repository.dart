import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import '../../domain/repositories/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? firebaseAuth,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  static const List<String> _scopes = [
    'email',
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
        scopeHint: _scopes,
      );

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final authorization = await googleUser.authorizationClient.authorizeScopes(_scopes);

      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: authorization.accessToken,
        idToken: googleAuth.idToken,
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

    final authHeaders = await account.authorizationClient.authorizationHeaders(_scopes);
    if (authHeaders == null) return null;
    
    return _AuthenticatedClient(authHeaders);
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
