/// Derives a key-encryption key (KEK) from a PIN using a memory-hard KDF.
///
/// Security rule: [pin] must NEVER be logged or stored.
/// The returned key bytes must be zeroized after use (best-effort in Dart).
abstract class KdfService {
  /// [pin]        — the user's app PIN (never the OS PIN).
  /// [saltBytes]  — random 16-byte salt, unique per vault.
  /// Returns 32 key bytes suitable for AES-256-GCM wrapping.
  Future<List<int>> deriveKey(String pin, List<int> saltBytes);

  /// Generates a cryptographically random salt for [deriveKey].
  List<int> generateSalt();
}
