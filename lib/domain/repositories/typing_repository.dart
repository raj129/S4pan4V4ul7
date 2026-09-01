/// Publishes and observes the "typing…" indicator.
///
/// Split out of [ThreadRepository] for the same reason as [PresenceRepository]:
/// typing is ephemeral, high-churn state that would move to Realtime Database
/// alongside presence if that swap is ever made.
abstract class TypingRepository {
  /// Set whether [uid] is currently typing in [threadId].
  Future<void> setTyping({
    required String threadId,
    required String uid,
    required bool isTyping,
  });

  /// Observe whether [otherUid] is typing in [threadId].
  Stream<bool> watchTyping({
    required String threadId,
    required String otherUid,
  });
}
