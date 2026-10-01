import 'dart:async';

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
      _sessionAccount = googleUser;

      final GoogleSignInAuthentication googleAuth = googleUser.authentication;
      final idToken = googleAuth.idToken;

      if (idToken == null || idToken.isEmpty) {
        throw const AuthException(
          'Google sign-in failed: no ID token was returned.',
        );
      }

      final AuthCredential credential = GoogleAuthProvider.credential(
        idToken: idToken,
      );

      final UserCredential userCredential =
          await _firebaseAuth.signInWithCredential(credential);

      final user = userCredential.user;
      if (user == null) {
        throw const AuthException('Firebase sign-in failed.');
      }

      // The account is already chosen; grant Drive access in the background
      // once so later Drive calls never re-authenticate.
      unawaited(warmUpDriveAuthorization(interactive: true));

      return AuthResult(
        userId: user.uid,
        email: user.email ?? '',
      );
    } on AuthException {
      rethrow;
    } on PlatformException catch (e) {
      // Credential Manager can reject the request when a second authorization
      // prompt is triggered unnecessarily; treat these as user cancellation.
      if (e.code == 'sign_in_canceled' ||
          e.code == 'sign_in_cancelled' ||
          e.code == '16' ||
          e.code == 'CANCELLED') {
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
    _clearCache();
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
  }

  // Shared across instances so every Drive caller reuses one authorization.
  static Map<String, String>? _cachedHeaders;
  static DateTime? _cachedAt;
  static GoogleSignInAccount? _sessionAccount;
  static Future<Map<String, String>?>? _inFlight;
  static DateTime? _failedAt;
  static const Duration _headerTtl = Duration(minutes: 45);
  static const Duration _failureTtl = Duration(minutes: 10);

  static void _clearCache() {
    _cachedHeaders = null;
    _cachedAt = null;
    _sessionAccount = null;
    _failedAt = null;
  }

  @override
  Future<void> warmUpDriveAuthorization({bool interactive = false}) async {
    try {
      await _driveHeaders(interactive: interactive);
    } catch (_) {}
  }

  Future<Map<String, String>?> _driveHeaders({required bool interactive}) {
    final cached = _cachedHeaders;
    final at = _cachedAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at) < _headerTtl) {
      return Future.value(cached);
    }
    final pending = _inFlight;
    if (pending != null) {
      // Join the running attempt rather than starting another prompt. An
      // explicit interactive request that finds it failed is made by the
      // caller (Settings), not chained here, so no second dialog appears.
      return pending;
    }
    // A recent silent attempt already failed: don't re-run account lookup on
    // every Drive call. Only an explicit interactive request retries early.
    final failedAt = _failedAt;
    if (!interactive &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < _failureTtl) {
      return Future.value(null);
    }

    final future = _fetchDriveHeaders(interactive: interactive);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<Map<String, String>?> _fetchDriveHeaders({
    required bool interactive,
  }) async {
    try {
      final account = _sessionAccount ??
          await _googleSignIn.attemptLightweightAuthentication();
      if (account == null) {
        _failedAt = DateTime.now();
        return null;
      }
      _sessionAccount = account;
      final allScopes = [..._authScopes, ..._driveScopes];
      final headers = await account.authorizationClient
          .authorizationHeaders(allScopes, promptIfNecessary: interactive);
      if (headers != null) {
        _cachedHeaders = headers;
        _cachedAt = DateTime.now();
        _failedAt = null;
      } else {
        _failedAt = DateTime.now();
      }
      return headers;
    } catch (_) {
      // Drive authorization failed (e.g. user did not grant drive scope).
      // Return null so callers fall back gracefully.
      _failedAt = DateTime.now();
      return null;
    }
  }

  @override
  Future<http.Client?> getAuthenticatedClient({bool interactive = false}) async {
    final headers = await _driveHeaders(interactive: interactive);
    if (headers == null) return null;
    return _AuthenticatedClient(headers);
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
