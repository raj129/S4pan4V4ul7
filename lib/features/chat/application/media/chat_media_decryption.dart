import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Whole-file authentication on a short-lived worker; no plaintext staging.
Future<Uint8List> decryptChatMediaInWorker(
  Uint8List ciphertext,
  SecretKey key,
) async {
  final keyBytes = Uint8List.fromList(await key.extractBytes());
  try {
    return await compute(
      _decrypt,
      _Input(TransferableTypedData.fromList([ciphertext]), keyBytes),
    );
  } finally {
    keyBytes.fillRange(0, keyBytes.length, 0);
  }
}

class _Input {
  const _Input(this.ciphertext, this.key);
  final TransferableTypedData ciphertext;
  final Uint8List key;
}

Future<Uint8List> _decrypt(_Input input) async {
  final bytes = input.ciphertext.materialize().asUint8List();
  try {
    final plain = await AesGcm.with256bits().decrypt(
      _box(bytes),
      secretKey: SecretKey(input.key),
    );
    return Uint8List.fromList(plain);
  } finally {
    input.key.fillRange(0, input.key.length, 0);
    bytes.fillRange(0, bytes.length, 0);
  }
}

SecretBox _box(Uint8List bytes) {
  if (bytes.length < 28) {
    throw const FormatException('Invalid encrypted attachment.');
  }
  return SecretBox(
    Uint8List.sublistView(bytes, 12, bytes.length - 16),
    nonce: Uint8List.sublistView(bytes, 0, 12),
    mac: Mac(Uint8List.sublistView(bytes, bytes.length - 16)),
  );
}
