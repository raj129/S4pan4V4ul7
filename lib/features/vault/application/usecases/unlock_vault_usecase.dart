import 'dart:convert';

import '../services/kdf_service.dart';
import 'package:photo_vault/core/crypto/models/wrapped_key.dart';
import 'package:photo_vault/core/crypto/services/crypto_service.dart';
import '../../domain/repositories/secure_storage_repository.dart';
import '../../domain/repositories/unlock_attempt_store.dart';
import '../../domain/repositories/vault_repository.dart';
import 'package:photo_vault/core/session/vault_session.dart';

/// Verifies app PIN by attempting to unwrap the stored VMK envelope.
///
/// Returns true when PIN is correct; false otherwise.
/// Raw key material is kept only within this use case and zeroed best-effort.
///
/// Wrong PINs are counted in [UnlockAttemptStore]; once the counter reaches
/// the schedule below, attempts are refused (returning false without touching
/// the key material) until the lockout expires.
class UnlockVaultUseCase {
  UnlockVaultUseCase({
    required VaultRepository vaultRepository,
    required SecureStorageRepository secureStorageRepository,
    required KdfService kdfService,
    required CryptoService cryptoService,
    required VaultSession vaultSession,
    UnlockAttemptStore? attemptStore,
    DateTime Function() clock = DateTime.now,
  }) : _vaultRepository = vaultRepository,
       _secureStorageRepository = secureStorageRepository,
       _kdfService = kdfService,
       _cryptoService = cryptoService,
       _vaultSession = vaultSession,
       _attempts = attemptStore ?? InMemoryUnlockAttemptStore(),
       _clock = clock;

  /// Lockout seconds indexed by consecutive failures; the last entry repeats.
  static const List<int> lockoutScheduleSeconds = <int>[
    0, 0, 0, 10, 30, 60, 300, 900, //
  ];

  final VaultRepository _vaultRepository;
  final SecureStorageRepository _secureStorageRepository;
  final KdfService _kdfService;
  final CryptoService _cryptoService;
  final VaultSession _vaultSession;
  final UnlockAttemptStore _attempts;
  final DateTime Function() _clock;

  /// Time left before another attempt is accepted, or null when unlocked.
  Future<Duration?> lockoutRemaining() async {
    final until = (await _attempts.load()).lockedUntil;
    if (until == null) return null;
    final remaining = until.difference(_clock());
    return remaining > Duration.zero ? remaining : null;
  }

  Future<bool> execute(String pin) async {
    if (await lockoutRemaining() != null) return false;
    final state = await _attempts.load();
    var attempted = false;
    try {
      final ok = await _verify(pin, onAttempt: () => attempted = true);
      if (ok) {
        if (state.failures != 0 || state.lockedUntil != null) {
          await _attempts.save(const UnlockAttemptState());
        }
      } else if (attempted) {
        await _recordFailure(state);
      }
      return ok;
    } catch (_) {
      if (attempted) await _recordFailure(state);
      return false;
    }
  }

  Future<void> _recordFailure(UnlockAttemptState state) {
    final failures = state.failures + 1;
    final index = failures.clamp(0, lockoutScheduleSeconds.length - 1);
    final seconds = lockoutScheduleSeconds[index];
    return _attempts.save(
      UnlockAttemptState(
        failures: failures,
        lockedUntil: seconds > 0
            ? _clock().add(Duration(seconds: seconds))
            : null,
      ),
    );
  }

  Future<bool> _verify(String pin, {required void Function() onAttempt}) async {
    List<int>? derivedKey;
    List<int>? vmk;
    try {
      final vaultId = await _vaultRepository.getActiveVaultId();
      if (vaultId == null || vaultId.isEmpty) return false;

      final wrappedRecord = await _secureStorageRepository.loadWrappedVmk(
        vaultId,
      );
      if (wrappedRecord == null) return false;

      final wrappedVmkB64 = wrappedRecord['wrappedVmk'];
      final nonceB64 = wrappedRecord['nonce'];
      final macB64 = wrappedRecord['mac'];
      final saltB64 = wrappedRecord['salt'];
      final encVersionRaw = wrappedRecord['encVersion'];
      if (wrappedVmkB64 == null ||
          nonceB64 == null ||
          macB64 == null ||
          saltB64 == null ||
          encVersionRaw == null) {
        return false;
      }

      onAttempt();
      final salt = base64Decode(saltB64);
      derivedKey = await _kdfService.deriveKey(pin, salt);

      final wrapped = WrappedKey(
        keyId: vaultId,
        wrappedBytes: base64Decode(wrappedVmkB64),
        nonce: base64Decode(nonceB64),
        mac: base64Decode(macB64),
        encryptionVersion: int.tryParse(encVersionRaw) ?? 1,
      );

      final aad = utf8.encode('$vaultId:vmk:v1');
      vmk = await _cryptoService.unwrapKey(wrapped, derivedKey, aad: aad);
      if (vmk.isEmpty) return false;
      _vaultSession.unlock(vaultId: vaultId, vmkBytes: vmk, pin: pin);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        derivedKey?.fillRange(0, derivedKey.length, 0);
      } catch (_) {}
      try {
        vmk?.fillRange(0, vmk.length, 0);
      } catch (_) {}
    }
  }
}
