import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/chat_camera_recovery.dart';
import 'package:photo_vault/crypto/services/chat_crypto_service.dart';

class _Crypto implements ChatCryptoService {
  @override
  Future<void> requireAccount(String uid) async {
    if (uid != 'alice') throw StateError('Account mismatch');
  }

  @override
  Future<Uint8List> encryptMedia({
    required String threadId,
    required Uint8List bytes,
  }) async => Uint8List.fromList([0xca, ...bytes.map((byte) => byte ^ 0xa5)]);
  @override
  Future<Uint8List> decryptMedia({
    required String threadId,
    required Uint8List encryptedBytes,
  }) async {
    if (encryptedBytes.isEmpty || encryptedBytes.first != 0xca) {
      throw const FormatException('Authentication failed');
    }
    return Uint8List.fromList(
      encryptedBytes.skip(1).map((byte) => byte ^ 0xa5).toList(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory directory;
  late ChatCameraRecovery recovery;
  var uid = 'alice';
  setUp(() async {
    uid = 'alice';
    directory = await Directory.systemTemp.createTemp('chat-camera-test-');
    recovery = ChatCameraRecovery(
      crypto: _Crypto(),
      currentUid: () => uid,
      directory: directory,
    );
  });
  tearDown(() async => directory.delete(recursive: true));

  test(
    'capture intent and ciphertext survive a new service instance',
    () async {
      await recovery.begin('alice', 'alice_bob', 'capture-1');
      expect(await recovery.intent('alice', 'alice_bob'), 'capture-1');
      final plain = Uint8List.fromList([1, 2, 3, 4]);
      await recovery.save('alice', 'alice_bob', 'capture-1', plain);
      final reopened = ChatCameraRecovery(
        crypto: _Crypto(),
        currentUid: () => uid,
        directory: directory,
      );
      expect(await reopened.intent('alice', 'alice_bob'), isNull);
      expect(await reopened.pending('alice', 'alice_bob'), ['capture-1']);
      expect(await reopened.read('alice', 'alice_bob', 'capture-1'), plain);
      final diskFiles = await directory
          .list(recursive: true)
          .where((e) => e is File)
          .toList();
      expect(await File(diskFiles.single.path).readAsBytes(), isNot(plain));
      await reopened.remove('alice', 'alice_bob', 'capture-1');
      expect(await reopened.pending('alice', 'alice_bob'), isEmpty);
    },
  );

  test(
    'account switch and wrong thread cannot expose recovered photo',
    () async {
      await recovery.save(
        'alice',
        'alice_bob',
        'capture-1',
        Uint8List.fromList([1]),
      );
      uid = 'bob';
      await expectLater(
        recovery.read('alice', 'alice_bob', 'capture-1'),
        throwsStateError,
      );
      uid = 'alice';
      await expectLater(
        recovery.read('alice', 'bob_carol', 'capture-1'),
        throwsStateError,
      );
      expect(await recovery.pending('alice', 'alice_carol'), isEmpty);
    },
  );

  test(
    'invalid identities and empty files are rejected before staging',
    () async {
      await expectLater(
        recovery.begin('alice', 'alice_bob', '../capture'),
        throwsArgumentError,
      );
      await expectLater(
        recovery.save('alice', 'alice_bob', 'capture-1', Uint8List(0)),
        throwsArgumentError,
      );
      expect(await recovery.pending('alice', 'alice_bob'), isEmpty);
    },
  );
}
