/// An identity private key encrypted under a PIN-derived key-encryption-key.
///
/// This is what makes chat history portable. The blob is safe to persist in
/// Firestore: recovering the key requires the user's PIN, which never leaves
/// the device. Signing in on a new device and entering the same PIN reproduces
/// the same identity key, which re-derives every thread key and makes the
/// existing message history readable again.
class WrappedIdentityKey {
  const WrappedIdentityKey({
    required this.ciphertextB64,
    required this.saltB64,
    required this.iterations,
  });

  /// base64(nonce ‖ ciphertext ‖ mac) of the identity private key.
  final String ciphertextB64;

  /// base64 PBKDF2 salt.
  final String saltB64;

  /// PBKDF2 iteration count used to derive the KEK.
  ///
  /// Persisted so the work factor can be raised in a future release without
  /// locking out users whose blob was written with the old cost.
  final int iterations;

  /// Default PBKDF2 cost. Deliberately high: the blob is stored server-side
  /// and a PIN carries very little entropy.
  static const defaultIterations = 210000;

  Map<String, dynamic> toFirestore() => {
        'wrappedIdentityKey': ciphertextB64,
        'salt': saltB64,
        'iterations': iterations,
      };

  static WrappedIdentityKey? fromFirestore(Map<String, dynamic>? data) {
    if (data == null) return null;
    final ciphertext = data['wrappedIdentityKey'] as String?;
    final salt = data['salt'] as String?;
    if (ciphertext == null || salt == null) return null;
    return WrappedIdentityKey(
      ciphertextB64: ciphertext,
      saltB64: salt,
      iterations: (data['iterations'] as num?)?.toInt() ?? defaultIterations,
    );
  }
}

/// Thrown when a wrapped identity key cannot be unwrapped with the given PIN.
class WrongPinException implements Exception {
  const WrongPinException();
  @override
  String toString() => 'Incorrect PIN — chat history could not be unlocked.';
}
