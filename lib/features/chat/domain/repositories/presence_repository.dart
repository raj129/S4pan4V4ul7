import '../entities/user_presence.dart';

/// Publishes and observes online state.
///
/// Split out of [UserRepository] so the backing store can change without
/// touching callers. The Firestore implementation needs a heartbeat and a
/// staleness window to approximate "went offline"; a Realtime Database
/// implementation would use `onDisconnect()` and need neither. Both details are
/// therefore implementation concerns and are absent from this interface.
abstract class PresenceRepository {
  /// Mark [uid] online and keep it online until [setOffline] is called.
  ///
  /// Implementations that require a heartbeat start it here. When
  /// [shareLastSeen] is false, other users must not be able to learn when
  /// [uid] was last active.
  Future<void> setOnline(String uid, {bool shareLastSeen = true});

  /// Mark [uid] offline and stop any heartbeat.
  ///
  /// When [shareLastSeen] is false the stored last-seen time is removed rather
  /// than updated.
  Future<void> setOffline(String uid, {bool shareLastSeen = true});

  /// Observe a single user's presence.
  Stream<UserPresence> watch(String uid);

  /// Observe several users at once.
  ///
  /// The emitted map always contains an entry for every requested uid, falling
  /// back to [UserPresence.offline] for users who have never published.
  Stream<Map<String, UserPresence>> watchMany(List<String> uids);

  /// Release timers and subscriptions.
  void dispose();
}
