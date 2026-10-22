import 'package:firebase_auth/firebase_auth.dart';

/// Signed-in Firebase uid, or null when signed out or Firebase is not ready.
///
/// Kept in the data layer so application services can take a plain
/// `String? Function()` instead of reaching for `FirebaseAuth.instance`.
String? firebaseCurrentUid() {
  try {
    return FirebaseAuth.instance.currentUser?.uid;
  } catch (_) {
    return null;
  }
}
