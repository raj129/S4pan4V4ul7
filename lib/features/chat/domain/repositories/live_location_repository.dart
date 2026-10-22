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

  /// Release listeners and resources.
  void dispose();
}
