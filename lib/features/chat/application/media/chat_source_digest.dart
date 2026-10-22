import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

/// Hash large original sources without blocking the chat UI or mutating inputs.
Future<String> chatSourceDigest(Uint8List bytes) {
  if (bytes.length < 512 * 1024) {
    return Future.value(sha256.convert(bytes).toString());
  }
  return compute(_digest, TransferableTypedData.fromList([bytes]));
}

String _digest(TransferableTypedData input) {
  final owned = input.materialize().asUint8List();
  try {
    return sha256.convert(owned).toString();
  } finally {
    owned.fillRange(0, owned.length, 0);
  }
}
