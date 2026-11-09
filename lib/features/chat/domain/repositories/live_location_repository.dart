import '../entities/live_location.dart';

/// Contract for publishing and observing encrypted live location sessions in a chat thread.
abstract class LiveLocationRepository {
  /// Start or replace a live location session for [userId] in [threadId] with a specific [duration].
  Future<void> startSession({
    required String sessionId,
    required String threadId,
    required String userId,
    required Duration duration,
    required LiveLocationPoint initialPoint,
  });

  /// Update the current coordinates for [userId] in [threadId].
  Future<void> updateLocation({
    required String sessionId,
    required String threadId,
    required String userId,
    required LiveLocationPoint point,
  });

  /// Terminate the live location session explicitly (sets isActive = false).
  Future<void> stopSession({
    required String sessionId,
    required String threadId,
    required String userId,
  });

  /// Watch active live location session for a specific user in a thread.
  Stream<LiveLocationSession?> watchUserSession({
    required String sessionId,
    required String threadId,
    required String userId,
  });

  /// Watch all active live location sessions within a thread.
  Stream<List<LiveLocationSession>> watchThreadSessions({
    required String threadId,
  });

  /// Ask the owner of an active session to refresh their location.
  Future<void> requestRefresh({
    required String sessionId,
    required String threadId,
    required String requesterUid,
  });

  /// Watch the refresh request associated with an active session.
  Stream<LiveLocationRefreshRequest?> watchRefreshRequest({
    required String sessionId,
    required String threadId,
  });

  /// Mark [requestToken] as handled by the session owner.
  Future<void> acknowledgeRefreshRequest({
    required String sessionId,
    required String threadId,
    required String requestToken,
  });

  /// Release listeners and resources.
  void dispose();
}
