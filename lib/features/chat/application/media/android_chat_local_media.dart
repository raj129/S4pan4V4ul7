import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'chat_media_cache.dart';
import './chat_source_digest.dart';

enum ChatMediaDirection { received, sent }

class ChatLocalMediaException implements Exception {
  const ChatLocalMediaException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => message;
}

class ChatLocalMediaMetadata {
  const ChatLocalMediaMetadata({
    required this.direction,
    required this.moved,
    this.sourceUri,
    this.sourceDigest,
    this.sourceFlags = 0,
    this.cachedSizeBytes,
  });
  final ChatMediaDirection direction;
  final bool moved;
  final String? sourceUri;
  final String? sourceDigest;
  final int sourceFlags;
  final int? cachedSizeBytes;

  factory ChatLocalMediaMetadata.fromMap(Map<Object?, Object?> map) {
    final direction = switch (map['direction']) {
      'received' => ChatMediaDirection.received,
      'sent' => ChatMediaDirection.sent,
      _ => throw const FormatException('Invalid local attachment identity.'),
    };
    if (map['moved'] is! bool ||
        (map['sourceUri'] != null && map['sourceUri'] is! String) ||
        (map['sourceDigest'] != null && map['sourceDigest'] is! String) ||
        (map['sourceFlags'] != null && map['sourceFlags'] is! int) ||
        (map['size'] != null && map['size'] is! int)) {
      throw const FormatException('Invalid local attachment metadata.');
    }
    return ChatLocalMediaMetadata(
      direction: direction,
      moved: map['moved'] as bool,
      sourceUri: map['sourceUri'] as String?,
      sourceDigest: map['sourceDigest'] as String?,
      sourceFlags: map['sourceFlags'] as int? ?? 0,
      cachedSizeBytes: map['size'] as int?,
    );
  }
}

/// Completed ciphertext is distinct from resumable native download staging.
class AndroidChatLocalMedia {
  const AndroidChatLocalMedia({
    this.channel = const MethodChannel('photo_vault/chat_local_media'),
    this.sourceChannel = const MethodChannel('photo_vault/chat_secure_media'),
    this.sourceReadTimeout = const Duration(seconds: 30),
  });
  final MethodChannel channel;
  final MethodChannel sourceChannel;
  final Duration sourceReadTimeout;

  Future<T?> _call<T>(String method, Map<String, Object?> arguments) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on PlatformException catch (error) {
      debugPrint('Chat local media stage=$method failure=${error.code}');
      throw ChatLocalMediaException(
        error.code,
        error.message ?? 'Local attachment unavailable. Please retry.',
      );
    }
  }

  Future<ChatLocalMediaMetadata?> metadata(String uid, String path) async {
    final value = await _call<Map<Object?, Object?>>('metadata', {
      'uid': uid,
      'path': path,
    });
    return value == null ? null : ChatLocalMediaMetadata.fromMap(value);
  }

  Future<Uint8List?> read(
    String uid,
    String path,
    ChatMediaDirection direction,
  ) async {
    final bytes = await _call<Uint8List>('read', {
      'uid': uid,
      'path': path,
      'direction': direction.name,
    });
    if (bytes == null) return null;
    if (bytes.length < 29 || bytes.length > 64 * 1024 * 1024) {
      throw const ChatLocalMediaException(
        'local_media_corrupt',
        'The local encrypted attachment is incomplete or damaged.',
      );
    }
    return Uint8List.fromList(bytes);
  }

  Future<void> put({
    required String uid,
    required String path,
    required ChatMediaDirection direction,
    required Uint8List ciphertext,
    String? sourceUri,
    String? sourceDigest,
    int sourceFlags = 0,
  }) => _call<void>('put', {
    'uid': uid,
    'path': path,
    'direction': direction.name,
    'bytes': ciphertext,
    'sourceUri': ?sourceUri,
    'sourceDigest': ?sourceDigest,
    'sourceFlags': sourceFlags,
  });

  Future<Uint8List> readOriginal(
    String uid,
    ChatLocalMediaMetadata metadata,
  ) async {
    final uri = metadata.sourceUri;
    final digest = metadata.sourceDigest;
    if (uri == null || digest == null) {
      throw const ChatLocalMediaException(
        'source_unavailable',
        'The original attachment source is unavailable.',
      );
    }
    try {
      final result = await sourceChannel
          .invokeMapMethod<Object?, Object?>('readSource', {
            'uid': uid,
            'sourceUri': uri,
            'maxBytes': 64 * 1024 * 1024 - 1024,
          })
          .timeout(sourceReadTimeout);
      final reply = result?['bytes'];
      if (reply is! Uint8List) {
        throw const FormatException('Invalid original attachment response.');
      }
      final owned = Uint8List.fromList(reply);
      try {
        if (owned.isEmpty ||
            owned.length > 64 * 1024 * 1024 - 1024 ||
            await chatSourceDigest(owned) != digest) {
          throw const ChatLocalMediaException(
            'source_changed',
            'The original file has changed. Using the encrypted sent copy.',
          );
        }
        return owned;
      } catch (_) {
        owned.fillRange(0, owned.length, 0);
        rethrow;
      }
    } on TimeoutException {
      throw const ChatLocalMediaException(
        'source_unavailable',
        'The original source did not respond. Using the encrypted sent copy.',
      );
    } on PlatformException catch (error) {
      debugPrint('Chat local media stage=source-read failure=${error.code}');
      throw ChatLocalMediaException(
        error.code,
        error.message ?? 'Original source permission or file is unavailable.',
      );
    }
  }

  Future<void> remove(String uid, String path) =>
      _call<void>('remove', {'uid': uid, 'path': path});
  Future<void> markMoved(String uid, String path) =>
      _call<void>('markMoved', {'uid': uid, 'path': path});
  Future<void> clear(String uid) => _call<void>('clear', {'uid': uid});
}

/// Android compatibility adapter: legacy ciphertext is migrated on valid reads.
class AndroidChatMediaCache extends ChatMediaCache {
  AndroidChatMediaCache({
    required this.localMedia,
    required this.currentUid,
    ChatMediaCache? legacy,
  }) : legacy = legacy ?? ChatMediaCache();

  final AndroidChatLocalMedia localMedia;
  final String? Function() currentUid;
  final ChatMediaCache legacy;

  (String, String) _identity(String key) {
    final uid = currentUid();
    if (uid == null || uid.isEmpty || !key.startsWith('$uid:')) {
      throw const ChatLocalMediaException(
        'account_changed',
        'Chat account changed. Reopen the attachment after signing in.',
      );
    }
    return (uid, key.substring(uid.length + 1));
  }

  @override
  Future<bool> wasMoved(String storagePath) async {
    final (uid, path) = _identity(storagePath);
    return (await localMedia.metadata(uid, path))?.moved == true ||
        await legacy.wasMoved(storagePath);
  }

  @override
  Future<Uint8List?> read(String storagePath) async {
    final (uid, path) = _identity(storagePath);
    if (await wasMoved(storagePath)) return null;
    final metadata = await localMedia.metadata(uid, path);
    final local = await localMedia.read(
      uid,
      path,
      metadata?.direction ?? ChatMediaDirection.received,
    );
    return local ?? await legacy.read(storagePath);
  }

  @override
  Future<void> write(String storagePath, Uint8List encryptedBytes) async {
    final (uid, path) = _identity(storagePath);
    if (await wasMoved(storagePath)) return;
    await localMedia.put(
      uid: uid,
      path: path,
      direction: ChatMediaDirection.received,
      ciphertext: encryptedBytes,
    );
    await legacy.remove(storagePath);
  }

  @override
  Future<void> remove(String storagePath) async {
    final (uid, path) = _identity(storagePath);
    await localMedia.remove(uid, path);
    await legacy.remove(storagePath);
  }

  @override
  Future<int> sizeOf(String storagePath) async {
    final (uid, path) = _identity(storagePath);
    final metadata = await localMedia.metadata(uid, path);
    if (metadata != null && !metadata.moved) {
      return metadata.cachedSizeBytes ?? 0;
    }
    return legacy.sizeOf(storagePath);
  }

  @override
  Future<void> markMoved(String storagePath) async {
    final (uid, path) = _identity(storagePath);
    await localMedia.markMoved(uid, path);
    await legacy.markMoved(storagePath);
  }

  @override
  void pin(String storagePath) => legacy.pin(storagePath);
  @override
  void unpin(String storagePath) => legacy.unpin(storagePath);

  @override
  Future<void> clear() async {
    final uid = currentUid();
    if (uid == null || uid.isEmpty) {
      throw const ChatLocalMediaException(
        'account_changed',
        'Sign in before removing local chat attachments.',
      );
    }
    await localMedia.clear(uid);
    await legacy.clear();
  }
}
