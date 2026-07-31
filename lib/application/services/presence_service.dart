import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/repositories/user_repository.dart';

/// Manages online/offline presence for the local user.
///
/// Call [activate] once the user is signed in.
/// Call [deactivate] on sign-out or app background.
class PresenceService {
  PresenceService({required this.userRepository});

  final UserRepository userRepository;

  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(minutes: 2);

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Mark user online and start a periodic heartbeat.
  Future<void> activate() async {
    final uid = _uid;
    if (uid == null) return;
    await userRepository.updatePresence(
      uid: uid,
      isOnline: true,
      lastSeen: DateTime.now().toUtc(),
    );
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _heartbeat());
  }

  /// Mark user offline and stop heartbeat.
  Future<void> deactivate() async {
    _heartbeatTimer?.cancel();
    final uid = _uid;
    if (uid == null) return;
    await userRepository.updatePresence(
      uid: uid,
      isOnline: false,
      lastSeen: DateTime.now().toUtc(),
    );
  }

  Future<void> _heartbeat() async {
    final uid = _uid;
    if (uid == null) return;
    await userRepository.updatePresence(
      uid: uid,
      isOnline: true,
      lastSeen: DateTime.now().toUtc(),
    );
  }

  void dispose() {
    _heartbeatTimer?.cancel();
  }
}
