import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../application/crypto/chat_crypto_service.dart';
import '../../domain/entities/live_location.dart';
import '../../domain/repositories/live_location_repository.dart';

/// Firestore implementation of [LiveLocationRepository] with end-to-end encryption.
///
/// Encrypted payloads are stored at `threads/{threadId}/live_locations/{sessionId}`.
/// Cloud Functions push alerts do not trigger on this subcollection, protecting
/// against FCM alert flooding and unexpected billing spikes.
class FirestoreLiveLocationRepository implements LiveLocationRepository {
  FirestoreLiveLocationRepository({
    FirebaseFirestore? firestore,
    required ChatCryptoService cryptoService,
  }) : _db =
           firestore ??
           FirebaseFirestore.instanceFor(
             app: Firebase.app(),
             databaseId: 'default1',
           ),
       _crypto = cryptoService;

  final FirebaseFirestore _db;
  final ChatCryptoService _crypto;

  DocumentReference<Map<String, dynamic>> _locationDoc(
    String threadId,
    String sessionId,
  ) => _db
      .collection('threads')
      .doc(threadId)
      .collection('live_locations')
      .doc(sessionId);

  CollectionReference<Map<String, dynamic>> _threadLocations(String threadId) =>
      _db.collection('threads').doc(threadId).collection('live_locations');

  @override
  Future<void> startSession({
    required String sessionId,
    required String threadId,
    required String userId,
    required Duration duration,
    required LiveLocationPoint initialPoint,
  }) async {
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(duration);

    final payloadJson = jsonEncode(initialPoint.toJson());
    final encryptedPayload = await _crypto.encryptMessage(
      threadId: threadId,
      plaintext: payloadJson,
    );

    await _locationDoc(threadId, sessionId).set({
      'sessionId': sessionId,
      'threadId': threadId,
      'userId': userId,
      'isActive': true,
      'startedAt': now.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'lastUpdatedAt': now.millisecondsSinceEpoch,
      'encryptedPayload': encryptedPayload,
    });
  }

  @override
  Future<void> updateLocation({
    required String sessionId,
    required String threadId,
    required String userId,
    required LiveLocationPoint point,
  }) async {
    final now = DateTime.now().toUtc();
    final payloadJson = jsonEncode(point.toJson());
    final encryptedPayload = await _crypto.encryptMessage(
      threadId: threadId,
      plaintext: payloadJson,
    );

    await _locationDoc(threadId, sessionId).update({
      'lastUpdatedAt': now.millisecondsSinceEpoch,
      'encryptedPayload': encryptedPayload,
    });
  }

  @override
  Future<void> stopSession({
    required String sessionId,
    required String threadId,
    required String userId,
  }) async {
    final ref = _locationDoc(threadId, sessionId);
    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    if (snapshot.data()?['userId'] != userId) {
      throw StateError('Cannot stop another user’s live-location session.');
    }
    final now = DateTime.now().toUtc();
    await ref.update({
      'isActive': false,
      'lastUpdatedAt': now.millisecondsSinceEpoch,
    });
  }

  @override
  Stream<LiveLocationSession?> watchUserSession({
    required String sessionId,
    required String threadId,
    required String userId,
  }) {
    return _locationDoc(threadId, sessionId).snapshots().asyncMap((snap) async {
      if (!snap.exists || snap.data() == null) return null;
      return _parseSession(
        threadId,
        snap.data()!,
        expectedSessionId: sessionId,
        expectedUserId: userId,
      );
    });
  }

  @override
  Stream<List<LiveLocationSession>> watchThreadSessions({
    required String threadId,
  }) {
    return _threadLocations(threadId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .asyncMap((querySnap) async {
          final sessions = <LiveLocationSession>[];
          for (final doc in querySnap.docs) {
            final parsed = await _parseSession(
              threadId,
              doc.data(),
              expectedSessionId: doc.id,
            );
            if (parsed != null && !parsed.isExpired) {
              sessions.add(parsed);
            }
          }
          return sessions;
        });
  }

  Future<LiveLocationSession?> _parseSession(
    String threadId,
    Map<String, dynamic> data, {
    required String expectedSessionId,
    String? expectedUserId,
  }) async {
    final sessionId = data['sessionId'];
    final userId = data['userId'];
    final startedAtMs = data['startedAt'];
    final expiresAtMs = data['expiresAt'];
    final lastUpdatedAtMs = data['lastUpdatedAt'];
    final encryptedPayload = data['encryptedPayload'];
    if (sessionId != expectedSessionId ||
        data['threadId'] != threadId ||
        sessionId is! String ||
        userId is! String ||
        (expectedUserId != null && userId != expectedUserId) ||
        data['isActive'] is! bool ||
        startedAtMs is! num ||
        expiresAtMs is! num ||
        lastUpdatedAtMs is! num ||
        encryptedPayload is! String) {
      throw const FormatException('Invalid live-location session document.');
    }

    final decrypted = await _crypto.decryptMessage(
      threadId: threadId,
      encryptedB64: encryptedPayload,
    );
    final json = jsonDecode(decrypted);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid encrypted live-location payload.');
    }

    return LiveLocationSession(
      sessionId: sessionId,
      threadId: threadId,
      userId: userId,
      isActive: data['isActive'] as bool,
      startedAt: DateTime.fromMillisecondsSinceEpoch(
        startedAtMs.toInt(),
        isUtc: true,
      ),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs.toInt(),
        isUtc: true,
      ),
      lastUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
        lastUpdatedAtMs.toInt(),
        isUtc: true,
      ),
      currentPoint: LiveLocationPoint.fromJson(json),
    );
  }

  @override
  void dispose() {
    // Firestore streams are closed by their listeners.
  }
}
