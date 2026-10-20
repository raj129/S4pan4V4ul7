import 'dart:math';

import 'package:cryptography/cryptography.dart';

import '../../application/services/kdf_service.dart';

/// PBKDF2-HMAC-SHA256 key derivation.
///
/// Parameters:
/// - 200 000 iterations (NIST SP 800-63B minimum for high-value credentials).
/// - 16-byte random salt (128 bits).
/// - 32-byte output (256 bits — AES-256-GCM key size).
///
/// Note: Argon2id is preferred for memory-hardness and GPU resistance.
/// PBKDF2 is used here because `argon2_flutter` requires native build setup.
/// The [KdfService] abstraction allows swapping to Argon2id without touching callers.
class Pbkdf2KdfService implements KdfService {
  Pbkdf2KdfService({int iterations = 200000})
    : _iterations = iterations,
      _pbkdf2 = Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: iterations,
        bits: 256,
      );

  final int _iterations;
  final Pbkdf2 _pbkdf2;
  final _random = Random.secure();

  @override
  Future<List<int>> deriveKey(String pin, List<int> saltBytes) async {
    // Security: pin is only processed in this scope; never logged.
    assert(!identical(pin, ''), 'PIN must not be empty');
    final secretKey = await _pbkdf2.deriveKey(
      secretKey: SecretKeyData(pin.codeUnits),
      nonce: saltBytes,
    );
    return secretKey.extractBytes();
  }

  @override
  List<int> generateSalt() =>
      List<int>.generate(16, (_) => _random.nextInt(256));

  int get iterations => _iterations;
}
