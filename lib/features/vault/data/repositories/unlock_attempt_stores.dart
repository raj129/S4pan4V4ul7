import '../../domain/repositories/unlock_attempt_store.dart';
import 'storage_keys.dart';
import 'storage_string_kv.dart';

class PersistentUnlockAttemptStore implements UnlockAttemptStore {
  PersistentUnlockAttemptStore(this._kv);

  final StorageStringKv _kv;

  @override
  Future<UnlockAttemptState> load() async {
    final failures = int.tryParse(
      await _kv.read(StorageKeys.unlockFailures) ?? '',
    );
    final untilMs = int.tryParse(
      await _kv.read(StorageKeys.unlockLockedUntil) ?? '',
    );
    return UnlockAttemptState(
      failures: failures ?? 0,
      lockedUntil: untilMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(untilMs),
    );
  }

  @override
  Future<void> save(UnlockAttemptState state) async {
    await _kv.write(StorageKeys.unlockFailures, state.failures.toString());
    final until = state.lockedUntil;
    if (until == null) {
      await _kv.delete(StorageKeys.unlockLockedUntil);
    } else {
      await _kv.write(
        StorageKeys.unlockLockedUntil,
        until.millisecondsSinceEpoch.toString(),
      );
    }
  }
}
