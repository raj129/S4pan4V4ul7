import '../../domain/repositories/auth_repository.dart';
import 'package:http/http.dart' as http;

class InMemoryAuthRepository implements AuthRepository {
  InMemoryAuthRepository({this.defaultSignedIn = false});

  bool _signedIn = false;
  final bool defaultSignedIn;

  @override
  Future<bool> isSignedIn() async {
    if (!_signedIn && defaultSignedIn) {
      _signedIn = true;
    }
    return _signedIn;
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    _signedIn = true;
    return const AuthResult(
      userId: 'demo-google-user',
      email: 'demo.user@gmail.com',
    );
  }

  @override
  Future<void> signOut() async {
    _signedIn = false;
  }

  @override
  Future<http.Client?> getAuthenticatedClient() async => null;
}
