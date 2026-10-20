import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../crypto/chat_crypto_service.dart';

/// Captured results outlive the chat route, but never cross account/thread
/// boundaries. The external camera's original staging is a separate boundary.
class ChatCameraRecovery {
  ChatCameraRecovery({
    required this.crypto,
    required this.currentUid,
    Directory? directory,
  }) : _directory = directory;

  final ChatCryptoService crypto;
  final String? Function() currentUid;
  final Directory? _directory;

  Future<void> _owner(String uid, String thread) async {
    if (uid.isEmpty ||
        currentUid() != uid ||
        !thread.split('_').contains(uid)) {
      throw StateError('Camera result belongs to another chat account.');
    }
    await crypto.requireAccount(uid);
  }

  Future<Directory> _dir(String uid, String thread) async {
    final base =
        _directory ??
        Directory(
          p.join(
            (await getApplicationSupportDirectory()).path,
            'chat_camera_recovery',
          ),
        );
    final key = sha256.convert(utf8.encode('$uid:$thread')).toString();
    final directory = Directory(p.join(base.path, key));
    await directory.create(recursive: true);
    return directory;
  }

  void _id(String id) {
    if (!RegExp(r'^[A-Za-z0-9-]{1,128}$').hasMatch(id)) {
      throw ArgumentError('Invalid captured attachment identity.');
    }
  }

  Future<void> _write(
    String uid,
    String thread,
    String name,
    Uint8List bytes,
  ) async {
    await _owner(uid, thread);
    final sealed = await crypto.encryptMedia(threadId: thread, bytes: bytes);
    await _owner(uid, thread);
    final target = File(p.join((await _dir(uid, thread)).path, name));
    final staging = File('${target.path}.next');
    try {
      await staging.writeAsBytes(sealed, flush: true);
      await _owner(uid, thread);
      await staging.rename(target.path);
    } finally {
      if (await staging.exists()) await staging.delete();
    }
  }

  Future<void> begin(String uid, String thread, String id) async {
    _id(id);
    final bytes = Uint8List.fromList(utf8.encode(id));
    try {
      await _write(uid, thread, 'intent.enc', bytes);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<String?> intent(String uid, String thread) async {
    await _owner(uid, thread);
    final file = File(p.join((await _dir(uid, thread)).path, 'intent.enc'));
    if (!await file.exists()) return null;
    final plain = await crypto.decryptMedia(
      threadId: thread,
      encryptedBytes: await file.readAsBytes(),
    );
    try {
      await _owner(uid, thread);
      final id = utf8.decode(plain);
      _id(id);
      return id;
    } finally {
      plain.fillRange(0, plain.length, 0);
    }
  }

  Future<void> endIntent(String uid, String thread) async {
    await _owner(uid, thread);
    final file = File(p.join((await _dir(uid, thread)).path, 'intent.enc'));
    if (await file.exists()) await file.delete();
  }

  Future<void> save(
    String uid,
    String thread,
    String id,
    Uint8List bytes,
  ) async {
    _id(id);
    if (bytes.isEmpty || bytes.length > 64 * 1024 * 1024 - 1024) {
      throw ArgumentError('Captured photo must be nonempty and below 64 MB.');
    }
    await _write(uid, thread, '$id.enc', bytes);
    await endIntent(uid, thread);
  }

  Future<List<String>> pending(String uid, String thread) async {
    await _owner(uid, thread);
    final ids = <String>[];
    await for (final entity in (await _dir(uid, thread)).list()) {
      if (entity is File &&
          p.basename(entity.path) != 'intent.enc' &&
          entity.path.endsWith('.enc')) {
        final id = p.basenameWithoutExtension(entity.path);
        _id(id);
        ids.add(id);
      }
    }
    return ids;
  }

  Future<Uint8List> read(String uid, String thread, String id) async {
    _id(id);
    await _owner(uid, thread);
    final file = File(p.join((await _dir(uid, thread)).path, '$id.enc'));
    if (await file.length() > 64 * 1024 * 1024) {
      throw const FormatException('Captured photo recovery file is too large.');
    }
    final plain = await crypto.decryptMedia(
      threadId: thread,
      encryptedBytes: await file.readAsBytes(),
    );
    try {
      await _owner(uid, thread);
      return plain;
    } catch (_) {
      plain.fillRange(0, plain.length, 0);
      rethrow;
    }
  }

  Future<void> remove(String uid, String thread, String id) async {
    _id(id);
    await _owner(uid, thread);
    final file = File(p.join((await _dir(uid, thread)).path, '$id.enc'));
    if (await file.exists()) await file.delete();
  }
}
