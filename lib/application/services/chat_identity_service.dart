import '../../crypto/services/chat_crypto_service.dart';
import '../../domain/entities/wrapped_identity_key.dart';
import '../../domain/repositories/user_repository.dart';

/// Outcome of reconciling this device's chat identity key with the copy stored
/// in Firestore.
enum IdentitySyncResult {
  /// Nothing to do — the device key is already backed up.
  upToDate,

  /// This device's existing key was wrapped and uploaded for the first time.
  /// Applies to installs that predate portable keys.
  uploaded,

  /// A key was downloaded and unwrapped, unlocking history on this device.
  restored,

  /// A brand-new identity key was created and backed up.
  created,

  /// A backup exists but could not be unwrapped, because no PIN was available.
  /// Chat history stays locked until the user supplies the PIN.
  pinRequired,

  /// A backup exists but the supplied PIN was wrong.
  wrongPin,
}

/// Keeps the chat identity key portable across reinstalls and devices.
///
/// Without this, the X25519 identity key only ever exists in one device's
/// secure storage: the Firestore ciphertext survives a reinstall but becomes
/// permanently undecryptable. Here the key is wrapped under a PIN-derived KEK
/// and stored in the owner-only `users/{uid}/private/keys` document, so signing
/// in with the same Google account and entering the same PIN restores it.
class ChatIdentityService {
  ChatIdentityService({
    required this.userRepository,
    required this.cryptoService,
  });

  final UserRepository userRepository;
  final ChatCryptoService cryptoService;

  /// Reconciles the local and remote copies of the identity key.
  ///
  /// [pin] is the vault PIN. It may be null when the vault is locked, in which
  /// case a restore cannot be performed and [IdentitySyncResult.pinRequired]
  /// is returned rather than silently creating a fresh key — creating one would
  /// orphan all existing history.
  Future<IdentitySyncResult> sync({required String uid, String? pin}) async {
    final remote = await userRepository.getWrappedIdentityKey(uid);
    final hasLocal = await cryptoService.hasIdentityKey();

    if (remote != null && !hasLocal) {
      // Fresh install or new device: the only way to read existing history.
      if (pin == null) return IdentitySyncResult.pinRequired;
      return _restore(uid: uid, wrapped: remote, pin: pin);
    }

    if (remote == null) {
      // Either a brand-new user, or an install that predates portable keys.
      final wasExisting = hasLocal;
      await cryptoService.getOrCreatePublicKey();
      if (pin == null) return IdentitySyncResult.pinRequired;
      await _upload(uid: uid, pin: pin);
      return wasExisting
          ? IdentitySyncResult.uploaded
          : IdentitySyncResult.created;
    }

    return IdentitySyncResult.upToDate;
  }

  Future<IdentitySyncResult> _restore({
    required String uid,
    required WrappedIdentityKey wrapped,
    required String pin,
  }) async {
    try {
      final publicKey = await cryptoService.importWrappedIdentityKey(
        wrapped: wrapped,
        pin: pin,
      );
      // Republish in case the profile's public key drifted from the identity.
      await userRepository.updatePublicKey(
        uid: uid,
        publicKeyBase64: publicKey,
      );
      return IdentitySyncResult.restored;
    } on WrongPinException {
      return IdentitySyncResult.wrongPin;
    }
  }

  Future<void> _upload({required String uid, required String pin}) async {
    final wrapped = await cryptoService.exportWrappedIdentityKey(pin);
    await userRepository.saveWrappedIdentityKey(uid: uid, wrapped: wrapped);
  }

  /// Re-wraps the *same* identity key under a new PIN.
  ///
  /// Called after a successful PIN change. Deriving the identity key from the
  /// PIN directly would have been simpler, but would destroy all chat history
  /// every time the PIN changed; re-wrapping keeps the key — and therefore the
  /// history — intact.
  Future<void> rewrapForNewPin({
    required String uid,
    required String newPin,
  }) async {
    if (!await cryptoService.hasIdentityKey()) return;
    await _upload(uid: uid, pin: newPin);
  }

  /// Forces a fresh identity key, abandoning all existing history.
  ///
  /// Only for the "I forgot my PIN" path, where the old key is unrecoverable
  /// anyway. The caller must warn the user first.
  Future<void> resetIdentity({required String uid, required String pin}) async {
    await cryptoService.clearIdentity();
    final publicKey = await cryptoService.getOrCreatePublicKey();
    await userRepository.updatePublicKey(uid: uid, publicKeyBase64: publicKey);
    await _upload(uid: uid, pin: pin);
  }
}
