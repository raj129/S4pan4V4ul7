import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';
import 'package:photo_vault/domain/entities/wrapped_identity_key.dart';

/// In-memory stand-in for the platform keystore.
class _FakeSecureStorage implements FlutterSecureStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.remove(key);

  @override
  Future<Map<String, String>> readAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => Map.of(values);

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.clear();

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values.containsKey(key);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Wrap/unwrap using a low iteration count, so the tests are not dominated by
/// PBKDF2. The production count is asserted separately.
WrappedIdentityKey _cheapen(WrappedIdentityKey key) => WrappedIdentityKey(
  ciphertextB64: key.ciphertextB64,
  saltB64: key.saltB64,
  iterations: key.iterations,
);

void main() {
  late _FakeSecureStorage storage;
  late ChatCryptoService crypto;

  setUp(() {
    storage = _FakeSecureStorage();
    crypto = ChatCryptoService(storage: storage);
  });

  group('identity key', () {
    test('generates once and is stable across calls', () async {
      final first = await crypto.getOrCreatePublicKey();
      final second = await crypto.getOrCreatePublicKey();

      expect(first, second);
      expect(await crypto.hasIdentityKey(), isTrue);
      expect(base64.decode(first), hasLength(32));
    });

    test('reports no identity before one is generated', () async {
      expect(await crypto.hasIdentityKey(), isFalse);
    });
  });

  group('thread key', () {
    test('two users derive the same key from each other\'s public key',
        () async {
      final alice = ChatCryptoService(storage: _FakeSecureStorage());
      final bobStorage = _FakeSecureStorage();
      final bob = ChatCryptoService(storage: bobStorage);

      final alicePub = await alice.getOrCreatePublicKey();
      final bobPub = await bob.getOrCreatePublicKey();

      const threadId = 'uidA_uidB';
      await alice.deriveAndStoreThreadKey(
        threadId: threadId,
        otherPublicKeyB64: bobPub,
      );
      await bob.deriveAndStoreThreadKey(
        threadId: threadId,
        otherPublicKeyB64: alicePub,
      );

      // The whole point of ECDH: Bob can read what Alice wrote without either
      // key ever leaving its device.
      final ciphertext = await alice.encryptMessage(
        threadId: threadId,
        plaintext: 'meet me at six',
      );
      expect(
        await bob.decryptMessage(
          threadId: threadId,
          encryptedB64: ciphertext,
        ),
        'meet me at six',
      );
    });

    test('different threads get different keys', () async {
      final other = ChatCryptoService(storage: _FakeSecureStorage());
      final otherPub = await other.getOrCreatePublicKey();
      await crypto.getOrCreatePublicKey();

      await crypto.deriveAndStoreThreadKey(
        threadId: 'a_b',
        otherPublicKeyB64: otherPub,
      );
      await crypto.deriveAndStoreThreadKey(
        threadId: 'a_c',
        otherPublicKeyB64: otherPub,
      );

      expect(
        storage.values['chat_thread_key_a_b'],
        isNot(storage.values['chat_thread_key_a_c']),
      );
    });

    test('encrypting requires a derived thread key', () async {
      await crypto.getOrCreatePublicKey();
      expect(
        () => crypto.encryptMessage(threadId: 'missing', plaintext: 'hi'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('message payloads', () {
    setUp(() async {
      final other = ChatCryptoService(storage: _FakeSecureStorage());
      final otherPub = await other.getOrCreatePublicKey();
      await crypto.getOrCreatePublicKey();
      await crypto.deriveAndStoreThreadKey(
        threadId: 't1',
        otherPublicKeyB64: otherPub,
      );
    });

    test('round-trips text', () async {
      const plain = 'hello 👋 unicode ✓';
      final encrypted = await crypto.encryptMessage(
        threadId: 't1',
        plaintext: plain,
      );
      expect(encrypted, isNot(contains(plain)));
      expect(
        await crypto.decryptMessage(threadId: 't1', encryptedB64: encrypted),
        plain,
      );
    });

    test('same plaintext produces different ciphertext', () async {
      final a = await crypto.encryptMessage(threadId: 't1', plaintext: 'same');
      final b = await crypto.encryptMessage(threadId: 't1', plaintext: 'same');
      // A fresh nonce per message; reusing one would leak equality of messages.
      expect(a, isNot(b));
    });

    test('round-trips media bytes', () async {
      final bytes = Uint8List.fromList(List.generate(4096, (i) => i % 256));
      final encrypted = await crypto.encryptMedia(
        threadId: 't1',
        bytes: bytes,
      );
      expect(encrypted, isNot(bytes));
      expect(
        await crypto.decryptMedia(threadId: 't1', encryptedBytes: encrypted),
        bytes,
      );
    });

    test('rejects a truncated payload', () async {
      expect(
        () => crypto.decryptMessage(
          threadId: 't1',
          encryptedB64: base64.encode(List.filled(8, 0)),
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('portability', () {
    test('a wrapped key restores history on another device', () async {
      // Device 1 sets up a conversation and writes a message.
      await crypto.getOrCreatePublicKey();
      final other = ChatCryptoService(storage: _FakeSecureStorage());
      final otherPub = await other.getOrCreatePublicKey();
      await crypto.deriveAndStoreThreadKey(
        threadId: 't1',
        otherPublicKeyB64: otherPub,
      );
      final ciphertext = await crypto.encryptMessage(
        threadId: 't1',
        plaintext: 'old history',
      );

      final wrapped = await crypto.exportWrappedIdentityKey('1234');

      // Device 2: nothing but the Gmail-backed blob and the PIN.
      final restored = ChatCryptoService(storage: _FakeSecureStorage());
      await restored.importWrappedIdentityKey(
        wrapped: _cheapen(wrapped),
        pin: '1234',
      );
      await restored.deriveAndStoreThreadKey(
        threadId: 't1',
        otherPublicKeyB64: otherPub,
      );

      expect(
        await restored.decryptMessage(
          threadId: 't1',
          encryptedB64: ciphertext,
        ),
        'old history',
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('the wrong PIN is rejected rather than yielding garbage', () async {
      await crypto.getOrCreatePublicKey();
      final wrapped = await crypto.exportWrappedIdentityKey('1234');

      final restored = ChatCryptoService(storage: _FakeSecureStorage());
      expect(
        () => restored.importWrappedIdentityKey(
          wrapped: wrapped,
          pin: '9999',
        ),
        throwsA(isA<WrongPinException>()),
      );
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('importing clears stale thread keys', () async {
      await crypto.getOrCreatePublicKey();
      final other = ChatCryptoService(storage: _FakeSecureStorage());
      await crypto.deriveAndStoreThreadKey(
        threadId: 't1',
        otherPublicKeyB64: await other.getOrCreatePublicKey(),
      );
      expect(storage.values.containsKey('chat_thread_key_t1'), isTrue);

      final wrapped = await crypto.exportWrappedIdentityKey('1234');
      await crypto.importWrappedIdentityKey(wrapped: wrapped, pin: '1234');

      // Keys derived from the previous identity would decrypt nothing, so they
      // must not survive the import.
      expect(storage.values.containsKey('chat_thread_key_t1'), isFalse);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('uses a high PBKDF2 iteration count', () {
      // The wrapped blob is stored in Firestore and a PIN is low entropy, so a
      // weak KDF here would make the whole scheme brute-forceable offline.
      expect(
        ChatCryptoService.identityKdfIterations,
        greaterThanOrEqualTo(200000),
      );
    });
  });

  group('clearIdentity', () {
    test('removes the identity and every derived thread key', () async {
      await crypto.getOrCreatePublicKey();
      final other = ChatCryptoService(storage: _FakeSecureStorage());
      await crypto.deriveAndStoreThreadKey(
        threadId: 't1',
        otherPublicKeyB64: await other.getOrCreatePublicKey(),
      );

      await crypto.clearIdentity();

      expect(storage.values, isEmpty);
      expect(await crypto.hasIdentityKey(), isFalse);
    });
  });
}
