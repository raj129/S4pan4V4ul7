import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/data/repositories_impl/firebase_auth_repository.dart';

class _FakeFirebaseAuth implements FirebaseAuth {
  _FakeFirebaseAuth(this._authEvents);

  final Stream<User?> _authEvents;
  User? _currentUser;

  @override
  Stream<User?> authStateChanges() => _authEvents;

  @override
  User? get currentUser => _currentUser;

  set currentUser(User? user) => _currentUser = user;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUser implements User {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('FirebaseAuthRepository.isSignedIn', () {
    test('waits for Firebase to restore the persisted user', () async {
      final events = StreamController<User?>.broadcast();
      addTearDown(events.close);
      final firebaseAuth = _FakeFirebaseAuth(events.stream);
      final repository = FirebaseAuthRepository(firebaseAuth: firebaseAuth);
      var completed = false;

      final result = repository.isSignedIn().then((signedIn) {
        completed = true;
        return signedIn;
      });
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);

      firebaseAuth.currentUser = _FakeUser();
      events.add(firebaseAuth.currentUser);
      expect(await result, isTrue);
    });

    test('returns false after Firebase restores an empty session', () async {
      final repository = FirebaseAuthRepository(
        firebaseAuth: _FakeFirebaseAuth(Stream<User?>.value(null)),
      );

      expect(await repository.isSignedIn(), isFalse);
    });
  });
}
