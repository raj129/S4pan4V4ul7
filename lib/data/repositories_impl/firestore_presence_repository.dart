import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../domain/entities/user_presence.dart';
import '../../domain/repositories/presence_repository.dart';

/// Firestore-backed presence, stored in a dedicated `presence/{uid}` collection.
///
/// Firestore has no equivalent of Realtime Database's `onDisconnect()`, so a
/// client that crashes or loses network never gets to write `isOnline: false`.
/// This implementation compensates with a heartbeat plus a staleness window:
/// a user counts as online only if they claim to be online *and* their last
/// heartbeat is recent. Both are private, because an RTDB implementation would
/// need neither.
class FirestorePresenceRepository implements PresenceRepository {
  FirestorePresenceRepository({FirebaseFirestore? firestore})
    : _db =
          firestore ??
          FirebaseFirestore.instanceFor(
            app: Firebase.app(),
            databaseId: 'default1',
          );

  final FirebaseFirestore _db;

  /// How often the local user republishes that they are alive.
  ///
  /// Kept short so a crashed client stops showing as "Online" within about a
  /// minute. At roughly ten users this costs ~29k writes/day worst case if
  /// everyone is online continuously, but in practice sessions are short and
  /// the heartbeat only runs in the foreground.
  static const _heartbeatInterval = Duration(seconds: 30);

  /// A heartbeat older than this means the client is gone.
  ///
  /// Two missed heartbeats, so a single slow write does not flicker the dot.
  static const _staleAfter = Duration(seconds: 75);

  /// How often watchers re-evaluate staleness.
  ///
  /// Necessary because Firestore emits nothing when a client simply stops
  /// writing — without a local ticker a peer would stay "Online" forever.
  static const _stalenessTick = Duration(seconds: 15);

  /// Firestore caps `whereIn` at 30 values per query.
  static const _whereInLimit = 30;

  CollectionReference<Map<String, dynamic>> get _presence =>
      _db.collection('presence');

  Timer? _heartbeatTimer;
  String? _heartbeatUid;

  @override
  Future<void> setOnline(String uid) async {
    _heartbeatTimer?.cancel();
    _heartbeatUid = uid;
    await _publish(uid, isOnline: true);
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      final current = _heartbeatUid;
      if (current == null) return;
      // Fire-and-forget: a failed heartbeat simply lets presence go stale,
      // which is the correct outcome anyway.
      _publish(current, isOnline: true).catchError((_) {});
    });
  }

  @override
  Future<void> setOffline(String uid) async {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatUid = null;
    await _publish(uid, isOnline: false);
  }

  Future<void> _publish(String uid, {required bool isOnline}) {
    return _presence.doc(uid).set({
      'uid': uid,
      'isOnline': isOnline,
      'lastSeen': DateTime.now().toUtc().millisecondsSinceEpoch,
    }, SetOptions(merge: true));
  }

  @override
  Stream<UserPresence> watch(String uid) => watchMany([
    uid,
  ]).map((byUid) => byUid[uid] ?? UserPresence.offline);

  @override
  Stream<Map<String, UserPresence>> watchMany(List<String> uids) {
    final unique = uids.where((u) => u.isNotEmpty).toSet().toList();
    if (unique.isEmpty) {
      return Stream.value(const <String, UserPresence>{});
    }

    final chunks = <List<String>>[];
    for (var i = 0; i < unique.length; i += _whereInLimit) {
      chunks.add(unique.skip(i).take(_whereInLimit).toList());
    }

    final raw = <String, _RawPresence>{};
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    Timer? ticker;
    late StreamController<Map<String, UserPresence>> controller;

    void publish() {
      if (controller.isClosed) return;
      final now = DateTime.now().toUtc();
      controller.add({
        for (final uid in unique)
          uid: raw[uid]?.resolve(now, _staleAfter) ?? UserPresence.offline,
      });
    }

    controller = StreamController<Map<String, UserPresence>>.broadcast(
      onListen: () {
        for (final chunk in chunks) {
          subs.add(
            _presence
                .where(FieldPath.documentId, whereIn: chunk)
                .snapshots()
                .listen((snap) {
                  for (final doc in snap.docs) {
                    raw[doc.id] = _RawPresence.fromMap(doc.data());
                  }
                  publish();
                }, onError: controller.addError),
          );
        }
        ticker = Timer.periodic(_stalenessTick, (_) => publish());
        publish();
      },
      onCancel: () async {
        ticker?.cancel();
        ticker = null;
        for (final sub in subs) {
          await sub.cancel();
        }
        subs.clear();
      },
    );

    return controller.stream;
  }

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatUid = null;
  }
}

/// The stored document, before the staleness window is applied.
class _RawPresence {
  const _RawPresence({required this.claimsOnline, required this.lastSeen});

  final bool claimsOnline;
  final DateTime lastSeen;

  factory _RawPresence.fromMap(Map<String, dynamic> data) => _RawPresence(
    claimsOnline: data['isOnline'] as bool? ?? false,
    lastSeen: DateTime.fromMillisecondsSinceEpoch(
      (data['lastSeen'] as int?) ?? 0,
      isUtc: true,
    ),
  );

  UserPresence resolve(DateTime now, Duration staleAfter) => UserPresence(
    isOnline: claimsOnline && now.difference(lastSeen) < staleAfter,
    lastSeen: lastSeen,
  );
}
