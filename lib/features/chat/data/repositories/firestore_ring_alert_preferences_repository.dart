import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/entities/ring_alert_preferences.dart';
import '../../domain/repositories/ring_alert_preferences_repository.dart';

class FirestoreRingAlertPreferencesRepository
    implements RingAlertPreferencesRepository {
  FirestoreRingAlertPreferencesRepository({FirebaseFirestore? firestore})
    : _db =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'default1',
          );

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _document(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('private')
      .doc('ringAlertPreferences');

  @override
  Future<RingAlertPreferences> getPreferences(String uid) async {
    final snapshot = await _document(uid).get();
    return RingAlertPreferences.fromFirestore(snapshot.data());
  }

  @override
  Future<void> savePreferences(String uid, RingAlertPreferences preferences) =>
      _document(uid).set(preferences.toFirestore());
}
