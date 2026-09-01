import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/repositories/presence_repository.dart';

/// Manages online/offline presence for the local user.
///
/// Call [activate] once the user is signed in.
/// Call [deactivate] on sign-out or app background.
///
/// This is lifecycle only. The heartbeat — and whether one is needed at all —
/// belongs to the [PresenceRepository] implementation, since a Realtime
/// Database version would use `onDisconnect()` and have no timer.
class PresenceService {
  PresenceService({required this.presenceRepository});

  final PresenceRepository presenceRepository;

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  /// Mark the signed-in user online.
  Future<void> activate() async {
    final uid = _uid;
    if (uid == null) return;
    await presenceRepository.setOnline(uid);
  }

  /// Mark the signed-in user offline.
  Future<void> deactivate() async {
    final uid = _uid;
    if (uid == null) return;
    await presenceRepository.setOffline(uid);
  }

  void dispose() {
    presenceRepository.dispose();
  }
}
