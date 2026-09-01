import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../domain/entities/wrapped_identity_key.dart';

/// Manages per-user ECDH identity keys and per-thread AES-GCM shared keys.
///
/// Key model:
///   1. Each user generates one random ECDH (X25519) identity key pair.
///      It is wrapped under a PIN-derived KEK and stored in Firestore so it can
///      be recovered on any device — see [exportWrappedIdentityKey] /
///      [importWrappedIdentityKey].
///   2. To start a thread both parties exchange public keys via Firestore profiles.
///   3. The ECDH shared secret is run through HKDF-SHA256, bound to the threadId,
///      to produce a per-thread AES-256-GCM key held in flutter_secure_storage.
///   4. Every message is encrypted with AES-256-GCM using that thread key.
///      The 12-byte nonce is prepended to the ciphertext.
///
/// Rekey: Delete the stored thread key to force a new ECDH round.
class ChatCryptoService {
  ChatCryptoService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _privateKeyStorageKey = 'chat_ecdh_private_key';
  static const _publicKeyStorageKey = 'chat_ecdh_public_key';
  static const _threadKeyPrefix = 'chat_thread_key_';

  /// Iteration count for the PIN → key-encryption-key derivation. Deliberately
  /// high: the wrapped blob lives in Firestore and a PIN is low entropy.
  static const identityKdfIterations = WrappedIdentityKey.defaultIterations;

  /// HKDF context string, so a thread key can never collide with any other
  /// key derived from the same ECDH secret.
  static const _hkdfContext = 'photo_vault/chat/thread-key/v1';

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _random = Random.secure();

  /// Decrypted-plaintext cache keyed by ciphertext, so repeated Firestore
  /// snapshots do not re-run AES-GCM over the whole visible history.
  final _plaintextCache = <String, String>{};
  static const _plaintextCacheLimit = 500;

  // ---------------------------------------------------------------------------
  // Identity key pair
  // ---------------------------------------------------------------------------

  /// Returns the local ECDH public key as base64, generating if needed.
  Future<String> getOrCreatePublicKey() async {
    final existing = await _storage.read(key: _publicKeyStorageKey);
    if (existing != null) return existing;
    final pair = await _x25519.newKeyPair();
    final pubBytes = await pair.extractPublicKey();
    final privBytes = await pair.extractPrivateKeyBytes();
    final pubB64 = base64.encode(pubBytes.bytes);
    final privB64 = base64.encode(privBytes);
    await _storage.write(key: _publicKeyStorageKey, value: pubB64);
    await _storage.write(key: _privateKeyStorageKey, value: privB64);
    return pubB64;
  }

  /// True when this device already holds an identity key pair.
  Future<bool> hasIdentityKey() async =>
      await _storage.read(key: _privateKeyStorageKey) != null;

  Future<SimpleKeyPair> _loadLocalKeyPair() async {
    final privB64 = await _storage.read(key: _privateKeyStorageKey);
    if (privB64 == null) {
      throw StateError('ECDH key pair not initialised. Call getOrCreatePublicKey first.');
    }
    final privBytes = base64.decode(privB64);
    return _x25519.newKeyPairFromSeed(privBytes);
  }

  // ---------------------------------------------------------------------------
  // Identity key portability (wrap / unwrap under a PIN-derived KEK)
  // ---------------------------------------------------------------------------

  /// Wraps this device's identity private key under a KEK derived from [pin].
  ///
  /// The returned blob is safe to store in Firestore: without the PIN it is
  /// just ciphertext. Restoring it on another device via
  /// [importWrappedIdentityKey] reproduces the same identity key, which
  /// re-derives every thread key and makes all past history readable again.
  Future<WrappedIdentityKey> exportWrappedIdentityKey(String pin) async {
    final privB64 = await _storage.read(key: _privateKeyStorageKey);
    if (privB64 == null) {
      throw StateError('No identity key to export.');
    }
    final salt = _randomBytes(16);
    final kek = await _deriveKek(pin: pin, salt: salt);
    final nonce = _generateNonce();
    final box = await _aesGcm.encrypt(
      base64.decode(privB64),
      secretKey: kek,
      nonce: nonce,
    );
    return WrappedIdentityKey(
      ciphertextB64: base64.encode(_concat(nonce, box.cipherText, box.mac.bytes)),
      saltB64: base64.encode(salt),
      iterations: identityKdfIterations,
    );
  }

  /// Unwraps [wrapped] with [pin] and installs it as this device's identity key.
  ///
  /// Any thread keys cached on this device are cleared, because they were
  /// derived from a different identity key and would decrypt nothing.
  /// Returns the restored public key as base64.
  ///
  /// Throws [WrongPinException] when the PIN does not match.
  Future<String> importWrappedIdentityKey({
    required WrappedIdentityKey wrapped,
    required String pin,
  }) async {
    final kek = await _deriveKek(
      pin: pin,
      salt: base64.decode(wrapped.saltB64),
      iterations: wrapped.iterations,
    );
    final bytes = base64.decode(wrapped.ciphertextB64);
    late final List<int> privBytes;
    try {
      privBytes = await _aesGcm.decrypt(_splitSecretBox(bytes), secretKey: kek);
    } on SecretBoxAuthenticationError {
      throw const WrongPinException();
    }

    await clearThreadKeys();
    final pair = await _x25519.newKeyPairFromSeed(privBytes);
    final pubBytes = await pair.extractPublicKey();
    final pubB64 = base64.encode(pubBytes.bytes);
    await _storage.write(key: _privateKeyStorageKey, value: base64.encode(privBytes));
    await _storage.write(key: _publicKeyStorageKey, value: pubB64);
    return pubB64;
  }

  Future<SecretKey> _deriveKek({
    required String pin,
    required List<int> salt,
    int iterations = identityKdfIterations,
  }) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: salt,
    );
  }

  // ---------------------------------------------------------------------------
  // Thread key management
  // ---------------------------------------------------------------------------

  /// Derive and store the shared AES key for a thread using ECDH + HKDF.
  /// [otherPublicKeyB64] is the remote user's public key from Firestore.
  Future<void> deriveAndStoreThreadKey({
    required String threadId,
    required String otherPublicKeyB64,
  }) async {
    final storageKey = '$_threadKeyPrefix$threadId';
    final existing = await _storage.read(key: storageKey);
    if (existing != null) return; // Already derived.

    final localPair = await _loadLocalKeyPair();
    final remotePublicKeyBytes = base64.decode(otherPublicKeyB64);
    final remotePublicKey = SimplePublicKey(remotePublicKeyBytes, type: KeyPairType.x25519);

    final sharedSecret = await _x25519.sharedSecretKey(
      keyPair: localPair,
      remotePublicKey: remotePublicKey,
    );

    // Expand the raw ECDH output into a proper AES key. Binding the threadId
    // into `info` guarantees distinct keys per thread even if the same pair of
    // users somehow shared a secret across contexts.
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final threadKey = await hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: const <int>[],
      info: utf8.encode('$_hkdfContext/$threadId'),
    );
    final keyBytes = await threadKey.extractBytes();
    await _storage.write(key: storageKey, value: base64.encode(keyBytes));
  }

  Future<SecretKey> _loadThreadKey(String threadId) async {
    final b64 = await _storage.read(key: '$_threadKeyPrefix$threadId');
    if (b64 == null) {
      throw StateError('No thread key for $threadId. Call deriveAndStoreThreadKey first.');
    }
    return SecretKey(base64.decode(b64));
  }

  /// Delete the stored thread key (triggers rekeying on next message).
  Future<void> deleteThreadKey(String threadId) async {
    await _storage.delete(key: '$_threadKeyPrefix$threadId');
    _plaintextCache.clear();
  }

  /// Drop every derived thread key. Used when the identity key changes.
  Future<void> clearThreadKeys() async {
    final all = await _storage.readAll();
    for (final key in all.keys) {
      if (key.startsWith(_threadKeyPrefix)) {
        await _storage.delete(key: key);
      }
    }
    _plaintextCache.clear();
  }

  /// Wipes the identity key pair and every derived thread key.
  ///
  /// This permanently abandons all existing chat history, so it is only for
  /// the forgotten-PIN path where the history is already unrecoverable.
  Future<void> clearIdentity() async {
    await clearThreadKeys();
    await _storage.delete(key: _privateKeyStorageKey);
    await _storage.delete(key: _publicKeyStorageKey);
  }

  // ---------------------------------------------------------------------------
  // Message encryption / decryption
  // ---------------------------------------------------------------------------

  /// Encrypt [plaintext] with the thread's AES-GCM key.
  /// Returns base64(nonce + ciphertext + mac).
  Future<String> encryptMessage({
    required String threadId,
    required String plaintext,
  }) async {
    final key = await _loadThreadKey(threadId);
    final nonce = _generateNonce();
    final secretBox = await _aesGcm.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    final encoded = base64.encode(
      _concat(nonce, secretBox.cipherText, secretBox.mac.bytes),
    );
    _cachePlaintext(encoded, plaintext);
    return encoded;
  }

  /// Decrypt a base64-encoded (nonce + ciphertext + mac) payload.
  ///
  /// Results are memoised by ciphertext: Firestore re-emits the whole visible
  /// window on every snapshot (including typing-triggered ones), and without
  /// this the UI would re-run AES-GCM over the full history each time.
  Future<String> decryptMessage({
    required String threadId,
    required String encryptedB64,
  }) async {
    final cached = _plaintextCache[encryptedB64];
    if (cached != null) return cached;

    final key = await _loadThreadKey(threadId);
    final plain = await _aesGcm.decrypt(
      _splitSecretBox(base64.decode(encryptedB64)),
      secretKey: key,
    );
    final text = utf8.decode(plain);
    _cachePlaintext(encryptedB64, text);
    return text;
  }

  void _cachePlaintext(String ciphertext, String plaintext) {
    if (_plaintextCache.length >= _plaintextCacheLimit) {
      // Cheap FIFO eviction — order is insertion order for a Dart LinkedHashMap.
      _plaintextCache.remove(_plaintextCache.keys.first);
    }
    _plaintextCache[ciphertext] = plaintext;
  }

  // ---------------------------------------------------------------------------
  // Media encryption / decryption
  // ---------------------------------------------------------------------------

  /// Encrypt raw [bytes] with the thread's AES-GCM key.
  /// Returns encrypted blob: nonce(12) + ciphertext + mac(16).
  Future<Uint8List> encryptMedia({
    required String threadId,
    required Uint8List bytes,
  }) async {
    final key = await _loadThreadKey(threadId);
    final nonce = _generateNonce();
    final secretBox = await _aesGcm.encrypt(bytes, secretKey: key, nonce: nonce);
    return _concat(nonce, secretBox.cipherText, secretBox.mac.bytes);
  }

  /// Decrypt a media blob previously returned by [encryptMedia].
  Future<Uint8List> decryptMedia({
    required String threadId,
    required Uint8List encryptedBytes,
  }) async {
    final key = await _loadThreadKey(threadId);
    final plain = await _aesGcm.decrypt(
      _splitSecretBox(encryptedBytes),
      secretKey: key,
    );
    return Uint8List.fromList(plain);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static const _nonceLength = 12;
  static const _macLength = 16;

  List<int> _generateNonce() =>
      List<int>.generate(_nonceLength, (_) => _random.nextInt(256));

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));

  /// Packs nonce ‖ ciphertext ‖ mac into one buffer.
  Uint8List _concat(List<int> nonce, List<int> cipherText, List<int> mac) {
    final out = Uint8List(nonce.length + cipherText.length + mac.length);
    out.setRange(0, nonce.length, nonce);
    out.setRange(nonce.length, nonce.length + cipherText.length, cipherText);
    out.setRange(nonce.length + cipherText.length, out.length, mac);
    return out;
  }

  /// Reverses [_concat] back into a [SecretBox].
  SecretBox _splitSecretBox(List<int> bytes) {
    if (bytes.length < _nonceLength + _macLength) {
      throw const FormatException('Encrypted payload is too short.');
    }
    return SecretBox(
      bytes.sublist(_nonceLength, bytes.length - _macLength),
      nonce: bytes.sublist(0, _nonceLength),
      mac: Mac(bytes.sublist(bytes.length - _macLength)),
    );
  }
}
