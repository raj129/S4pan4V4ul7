import 'dart:async';
import 'dart:isolate';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// Whole-file authentication on a small, reused worker pool; no plaintext
/// staging. Workers are reused so a screen of thumbnails does not pay an
/// isolate spawn per image, and exit after a short idle period.
Future<Uint8List> decryptChatMediaInWorker(
  Uint8List ciphertext,
  SecretKey key,
) async {
  final keyBytes = Uint8List.fromList(await key.extractBytes());
  try {
    return await _pool.decrypt(
      TransferableTypedData.fromList([ciphertext]),
      keyBytes,
    );
  } finally {
    keyBytes.fillRange(0, keyBytes.length, 0);
  }
}

final _DecryptPool _pool = _DecryptPool(size: 2);

class _DecryptPool {
  _DecryptPool({required this.size});

  final int size;
  final List<_Worker> _workers = [];
  Timer? _idle;

  Future<Uint8List> decrypt(TransferableTypedData data, Uint8List key) async {
    _idle?.cancel();
    final worker = await _pick();
    try {
      return await worker.decrypt(data, Uint8List.fromList(key));
    } finally {
      _scheduleIdle();
    }
  }

  Future<void> _gate = Future<void>.value();

  // Serialized so a burst of requests cannot spawn more than [size] workers.
  Future<_Worker> _pick() {
    final result = _gate.then((_) => _pickLocked());
    _gate = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<_Worker> _pickLocked() async {
    _workers.removeWhere((w) => w.closed);
    if (_workers.isEmpty ||
        (_workers.length < size && _workers.every((w) => w.busy > 0))) {
      final worker = await _Worker.spawn();
      _workers.add(worker);
      return worker;
    }
    return _workers.reduce((a, b) => a.busy <= b.busy ? a : b);
  }

  void _scheduleIdle() {
    _idle?.cancel();
    _idle = Timer(const Duration(seconds: 20), () {
      if (_workers.any((w) => w.busy > 0)) {
        _scheduleIdle();
        return;
      }
      for (final worker in _workers) {
        worker.close();
      }
      _workers.clear();
    });
  }
}

class _Worker {
  _Worker._(this._isolate, this._send, this._receive) {
    _receive.listen(_onMessage);
  }

  final Isolate _isolate;
  final SendPort _send;
  final ReceivePort _receive;
  final Map<int, Completer<Uint8List>> _pending = {};
  int _next = 0;
  bool closed = false;

  int get busy => _pending.length;

  static Future<_Worker> spawn() async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(_entry, ready.sendPort);
    final send = await ready.first as SendPort;
    final replies = ReceivePort();
    send.send(replies.sendPort);
    return _Worker._(isolate, send, replies);
  }

  Future<Uint8List> decrypt(TransferableTypedData data, Uint8List key) {
    if (closed) throw StateError('Decrypt worker closed.');
    final id = _next++;
    final completer = Completer<Uint8List>();
    _pending[id] = completer;
    _send.send([id, data, key]);
    return completer.future;
  }

  void _onMessage(Object? message) {
    if (message is! List || message.length != 3) return;
    final completer = _pending.remove(message[0] as int);
    if (completer == null) return;
    final error = message[2];
    if (error != null) {
      completer.completeError(_rebuild(error));
    } else {
      completer.complete(
        (message[1] as TransferableTypedData).materialize().asUint8List(),
      );
    }
  }

  void close() {
    if (closed) return;
    closed = true;
    _receive.close();
    _isolate.kill(priority: Isolate.immediate);
    for (final completer in _pending.values) {
      completer.completeError(StateError('Decrypt worker closed.'));
    }
    _pending.clear();
  }
}

// Exceptions cannot cross the isolate boundary intact; restore the types
// callers branch on (authentication, format).
Object _rebuild(Object error) {
  if (error is List && error.length == 2) {
    return switch (error[0]) {
      'auth' => SecretBoxAuthenticationError(),
      'format' => FormatException(error[1] as String),
      _ => StateError(error[1] as String),
    };
  }
  return StateError('Attachment decryption failed.');
}

Future<void> _entry(SendPort ready) async {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  SendPort? reply;
  await for (final message in commands) {
    if (message is SendPort) {
      reply = message;
      continue;
    }
    if (message is! List || reply == null) continue;
    final id = message[0] as int;
    final key = message[2] as Uint8List;
    try {
      final plain = await _decrypt(
        (message[1] as TransferableTypedData).materialize().asUint8List(),
        key,
      );
      reply.send([
        id,
        TransferableTypedData.fromList([plain]),
        null,
      ]);
    } on SecretBoxAuthenticationError {
      reply.send([
        id,
        null,
        const ['auth', ''],
      ]);
    } on FormatException catch (error) {
      reply.send([
        id,
        null,
        ['format', error.message],
      ]);
    } catch (_) {
      reply.send([
        id,
        null,
        const ['other', 'Attachment decryption failed.'],
      ]);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }
}

Future<Uint8List> _decrypt(Uint8List bytes, Uint8List key) async {
  try {
    final plain = await AesGcm.with256bits().decrypt(
      _box(bytes),
      secretKey: SecretKey(key),
    );
    return Uint8List.fromList(plain);
  } finally {
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
