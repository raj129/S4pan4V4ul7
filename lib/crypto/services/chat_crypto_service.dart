import 'dart:convert';
import 'dart:typed_data';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Manages per-user ECDH identity keys and per-thread AES-GCM shared keys.
///
/// Key model:
///   1. Each device generates a static ECDH (X25519) key pair on first sign-in.
///   2. To start a thread both parties exchange public keys via Firestore profiles.
///   3. A shared secret is derived from ECDH and stored as a per-thread
///      AES-256-GCM key in flutter_secure_storage (keyed by threadId).
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

  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _random = Random.secure();

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

  Future<SimpleKeyPair> _loadLocalKeyPair() async {
    final privB64 = await _storage.read(key: _privateKeyStorageKey);
    if (privB64 == null) {
      throw StateError('ECDH key pair not initialised. Call getOrCreatePublicKey first.');
    }
    final privBytes = base64.decode(privB64);
    return _x25519.newKeyPairFromSeed(privBytes);
  }

  // ---------------------------------------------------------------------------
  // Thread key management
  // ---------------------------------------------------------------------------

  /// Derive and store the shared AES key for a thread using ECDH.
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
    final sharedBytes = await sharedSecret.extractBytes();

    // Use first 32 bytes as AES-256 key material.
    final keyBytes = Uint8List.fromList(sharedBytes.take(32).toList());
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
    final combined = Uint8List(nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(nonce.length, nonce.length + secretBox.cipherText.length, secretBox.cipherText);
    combined.setRange(
      nonce.length + secretBox.cipherText.length,
      combined.length,
      secretBox.mac.bytes,
    );
    return base64.encode(combined);
  }

  /// Decrypt a base64-encoded (nonce + ciphertext + mac) payload.
  Future<String> decryptMessage({
    required String threadId,
    required String encryptedB64,
  }) async {
    final key = await _loadThreadKey(threadId);
    final bytes = base64.decode(encryptedB64);
    const nonceLen = 12;
    const macLen = 16;
    final nonce = bytes.sublist(0, nonceLen);
    final mac = Mac(bytes.sublist(bytes.length - macLen));
    final cipherText = bytes.sublist(nonceLen, bytes.length - macLen);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plainBytes = await _aesGcm.decrypt(secretBox, secretKey: key);
    return utf8.decode(plainBytes);
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
    final combined = Uint8List(nonce.length + secretBox.cipherText.length + secretBox.mac.bytes.length);
    combined.setRange(0, nonce.length, nonce);
    combined.setRange(nonce.length, nonce.length + secretBox.cipherText.length, secretBox.cipherText);
    combined.setRange(
      nonce.length + secretBox.cipherText.length,
      combined.length,
      secretBox.mac.bytes,
    );
    return combined;
  }

  /// Decrypt a media blob previously returned by [encryptMedia].
  Future<Uint8List> decryptMedia({
    required String threadId,
    required Uint8List encryptedBytes,
  }) async {
    final key = await _loadThreadKey(threadId);
    const nonceLen = 12;
    const macLen = 16;
    final nonce = encryptedBytes.sublist(0, nonceLen);
    final mac = Mac(encryptedBytes.sublist(encryptedBytes.length - macLen));
    final cipherText = encryptedBytes.sublist(nonceLen, encryptedBytes.length - macLen);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final plain = await _aesGcm.decrypt(secretBox, secretKey: key);
    return Uint8List.fromList(plain);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  List<int> _generateNonce() {
    return List<int>.generate(12, (_) => _random.nextInt(256));
  }
}
