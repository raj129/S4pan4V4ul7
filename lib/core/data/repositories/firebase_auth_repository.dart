import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../../domain/repositories/auth_repository.dart';

typedef DriveTokenFunctionInvoker =
    Future<Object?> Function(String name, {Object? data});
typedef DriveServerAuthCodeProvider = Future<String?> Function();

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository({
    FirebaseAuth? firebaseAuth,
    FirebaseFunctions? firebaseFunctions,
    DriveTokenFunctionInvoker? driveTokenFunctionInvoker,
    DriveServerAuthCodeProvider? driveServerAuthCodeProvider,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _firebaseFunctions = firebaseFunctions,
       _driveTokenFunctionInvoker = driveTokenFunctionInvoker,
       _driveServerAuthCodeProvider = driveServerAuthCodeProvider;

  final FirebaseAuth _firebaseAuth;
  final FirebaseFunctions? _firebaseFunctions;
  final DriveTokenFunctionInvoker? _driveTokenFunctionInvoker;
  final DriveServerAuthCodeProvider? _driveServerAuthCodeProvider;
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  // Only the email scope is required to obtain a Firebase credential.
  // Requesting drive.appdata here causes Android's Credential Manager to
  // reject the entire flow (error code 16 / reauth failed).
  static const List<String> _authScopes = ['email'];
  static const List<String> _driveScopes = [
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  static const String _functionsRegion = 'asia-south1';

  @override
  Future<bool> isSignedIn() async {
    await _firebaseAuth.authStateChanges().first;
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
      final UserCredential userCredential = await _firebaseAuth
          .signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        throw const AuthException('Firebase sign-in failed.');
      }

      return AuthResult(userId: user.uid, email: user.email ?? '');
    } on AuthException {
      rethrow;
    } on PlatformException catch (e) {
      if (e.code == 'sign_in_canceled' ||
          e.code == 'sign_in_cancelled' ||
          e.code == '16' ||
          e.code == 'CANCELLED') {
        throw const AuthException('Sign-in was cancelled. Please try again.');
      }
      throw AuthException('Google sign-in failed: ${e.message ?? e.code}');
    } catch (e) {
      throw AuthException('Google sign-in failed: $e');
    }
  }

  static String? _cachedAccessToken;
  static DateTime? _accessTokenExpiresAt;
  static GoogleSignInAccount? _sessionAccount;
  static Future<String?>? _inFlight;
  static DateTime? _failedAt;
  static const Duration _failureTtl = Duration(minutes: 10);
  static const Duration _expirySafetyMargin = Duration(minutes: 1);

  static void _clearCache() {
    _cachedAccessToken = null;
    _accessTokenExpiresAt = null;
    _sessionAccount = null;
    _failedAt = null;
    _inFlight = null;
  }

  @visibleForTesting
  static void clearDriveAuthorizationCacheForTesting() => _clearCache();

  FirebaseFunctions get _functions =>
      _firebaseFunctions ??
      FirebaseFunctions.instanceFor(
        app: _firebaseAuth.app,
        region: _functionsRegion,
      );

  Future<Object?> _callDriveFunction(String name, {Object? data}) async {
    final invoker = _driveTokenFunctionInvoker;
    if (invoker != null) return invoker(name, data: data);
    final result = await _functions.httpsCallable(name).call<Object?>(data);
    return result.data;
  }

  Future<String?> _driveAccessToken({required bool interactive}) async {
    final cached = _cachedAccessToken;
    final expiresAt = _accessTokenExpiresAt;
    if (cached != null &&
        expiresAt != null &&
        DateTime.now().add(_expirySafetyMargin).isBefore(expiresAt)) {
      return cached;
    }

    final pending = _inFlight;
    if (pending != null) {
      final token = await pending;
      if (token != null || !interactive) return token;
    }

    final failedAt = _failedAt;
    if (!interactive &&
        failedAt != null &&
        DateTime.now().difference(failedAt) < _failureTtl) {
      return null;
    }

    final future = _fetchDriveAccessToken(interactive: interactive);
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) _inFlight = null;
    }
  }

  Future<String?> _fetchDriveAccessToken({required bool interactive}) async {
    try {
      final response = await _callDriveFunction('getGoogleDriveAccessToken');
      return _cacheAccessToken(response);
    } on FirebaseFunctionsException catch (error) {
      if (error.code != 'failed-precondition') rethrow;
      _failedAt = DateTime.now();
      if (!interactive) return null;
    }

    if (!interactive) return null;
    final serverAuthCode =
        await (_driveServerAuthCodeProvider?.call() ??
            _authorizeDriveOnDevice());
    if (serverAuthCode == null || serverAuthCode.isEmpty) {
      throw const AuthException(
        'Google Drive did not provide an authorization code. Please try again.',
      );
    }
    final response = await _callDriveFunction(
      'connectGoogleDrive',
      data: {'serverAuthCode': serverAuthCode},
    );
    return _cacheAccessToken(response);
  }

  String _cacheAccessToken(Object? response) {
    if (response is! Map) {
      throw const AuthException('Google Drive returned an invalid response.');
    }
    final token = response['accessToken'];
    final expiresIn = response['expiresIn'];
    if (token is! String ||
        token.isEmpty ||
        expiresIn is! num ||
        !expiresIn.isFinite ||
        expiresIn <= 0) {
      throw const AuthException(
        'Google Drive returned an invalid access token.',
      );
    }
    _cachedAccessToken = token;
    _accessTokenExpiresAt = DateTime.now().add(
      Duration(seconds: expiresIn.floor()),
    );
    _failedAt = null;
    return token;
  }

  Future<String?> _authorizeDriveOnDevice() async {
    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) {
      throw const AuthException('Sign in before connecting Google Drive.');
    }

    var account =
        _sessionAccount ??
        await _googleSignIn.attemptLightweightAuthentication();
    account ??= await _googleSignIn.authenticate(scopeHint: _authScopes);
    final firebaseEmail = firebaseUser.email?.toLowerCase();
    if (firebaseEmail != null && account.email.toLowerCase() != firebaseEmail) {
      throw const AuthException(
        'Choose the same Google account that is signed in to the app.',
      );
    }
    _sessionAccount = account;

    final authorization = await account.authorizationClient.authorizeServer(
      _driveScopes,
    );
    return authorization?.serverAuthCode;
  }

  @override
  Future<void> warmUpDriveAuthorization({bool interactive = false}) async {
    await _driveAccessToken(interactive: interactive);
  }

  @override
  Future<void> signOut() async {
    try {
      final result = await _callDriveFunction('disconnectGoogleDrive');
      if (result is Map && result['revoked'] == false) {
        debugPrint('Google Drive authorization could not be revoked remotely.');
      }
    } catch (error) {
      // Local sign-out must still complete if the device is offline.
      debugPrint('Google Drive disconnect failed during sign-out: $error');
    }
    _clearCache();
    try {
      await _googleSignIn.signOut();
    } finally {
      await _firebaseAuth.signOut();
    }
  }

  @override
  Future<http.Client?> getAuthenticatedClient({
    bool interactive = false,
  }) async {
    final accessToken = await _driveAccessToken(interactive: interactive);
    if (accessToken == null) return null;
    return _AuthenticatedClient(accessToken);
  }
}

class _AuthenticatedClient extends http.BaseClient {
  _AuthenticatedClient(this._accessToken);

  final String _accessToken;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _inner.send(request);
  }
}
