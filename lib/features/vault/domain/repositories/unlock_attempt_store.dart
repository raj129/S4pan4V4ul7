/// Failed PIN attempts and the time before which unlocking is refused.
class UnlockAttemptState {
  const UnlockAttemptState({this.failures = 0, this.lockedUntil});

  final int failures;
  final DateTime? lockedUntil;
}

/// Persists [UnlockAttemptState] so a lockout survives screen rebuilds and
/// app restarts.
abstract class UnlockAttemptStore {
  Future<UnlockAttemptState> load();
  Future<void> save(UnlockAttemptState state);
}

/// Non-persistent store; the default for tests and in-memory configurations.
class InMemoryUnlockAttemptStore implements UnlockAttemptStore {
  UnlockAttemptState _state = const UnlockAttemptState();

  @override
  Future<UnlockAttemptState> load() async => _state;

  @override
  Future<void> save(UnlockAttemptState state) async => _state = state;
}
