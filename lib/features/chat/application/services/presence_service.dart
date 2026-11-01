import 'package:flutter/foundation.dart';

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
  PresenceService({
    required this.presenceRepository,
    required String? Function() currentUid,
    ValueNotifier<bool>? shareLastSeen,
  }) : _currentUid = currentUid,
       _ownsShareLastSeen = shareLastSeen == null,
       shareLastSeen = shareLastSeen ?? ValueNotifier<bool>(true);

  final PresenceRepository presenceRepository;
  final String? Function() _currentUid;
  final bool _ownsShareLastSeen;

  /// The local "Show last seen" privacy setting. Also read by
  /// `LastSeenPrivacyPresenceRepository` to hide others' last seen in return.
  final ValueNotifier<bool> shareLastSeen;

  bool _active = false;

  String? get _uid => _currentUid();

  /// Mark the signed-in user online.
  Future<void> activate() async {
    final uid = _uid;
    if (uid == null) return;
    _active = true;
    await presenceRepository.setOnline(uid, shareLastSeen: shareLastSeen.value);
  }

  /// Mark the signed-in user offline.
  Future<void> deactivate() async {
    final uid = _uid;
    if (uid == null) return;
    _active = false;
    await presenceRepository.setOffline(
      uid,
      shareLastSeen: shareLastSeen.value,
    );
  }

  /// Applies a change to the "Show last seen" setting and republishes, so
  /// turning it off immediately removes the stored last-seen time.
  Future<void> setShareLastSeen(bool share) async {
    if (shareLastSeen.value == share) return;
    shareLastSeen.value = share;
    final uid = _uid;
    if (uid == null) return;
    if (_active) {
      await presenceRepository.setOnline(uid, shareLastSeen: share);
    } else {
      await presenceRepository.setOffline(uid, shareLastSeen: share);
    }
  }

  void dispose() {
    presenceRepository.dispose();
    // An injected notifier is shared (e.g. with the privacy decorator) and is
    // owned by whoever created it.
    if (_ownsShareLastSeen) shareLastSeen.dispose();
  }
}
