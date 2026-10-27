import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/local_sticker.dart';

abstract interface class StickerKeyStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class _FlutterSecureStickerKeyStore implements StickerKeyStore {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

class LocalStickerPackRepository {
  LocalStickerPackRepository({
    required String userId,
    Directory? rootDirectory,
    StickerKeyStore? keyStore,
  }) : _userKey = sha256.convert(utf8.encode(userId)).toString(),
       _rootDirectory = rootDirectory,
       _keyStore = keyStore ?? _FlutterSecureStickerKeyStore();

  static const maxStickerBytes = 4 * 1024 * 1024;
  static const maxPackBytes = 32 * 1024 * 1024;
  static const maxStickers = 100;
  static const _maxManifestBytes = 128 * 1024;
  static const _keyPrefix = 'chat_stickers_key_';
  static const _extensions = {'gif', 'webp', 'png', 'jpg', 'jpeg'};
  static final Map<String, Future<void>> _queues = {};

  final String _userKey;
  final Directory? _rootDirectory;
  final StickerKeyStore _keyStore;
  final AesGcm _cipher = AesGcm.with256bits();
  final Uuid _uuid = const Uuid();

  Future<List<LocalSticker>> list() => _serialized(() async {
    final manifest = await _readManifest();
    manifest.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return List.unmodifiable(manifest);
  });

  Future<Uint8List> readBytes(LocalSticker sticker) => _serialized(() async {
    final path = await _directory();
    if (sticker.fileName != '${sticker.id}.enc') {
      throw const FormatException('Invalid sticker file path.');
    }
    final encrypted = await File(
      '${path.path}${Platform.pathSeparator}${sticker.fileName}',
    ).readAsBytes();
    if (encrypted.length < 28) {
      throw const FormatException('Saved sticker data is incomplete.');
    }
    final secretKey = await _getKey();
    final nonce = encrypted.sublist(0, 12);
    final mac = Mac(encrypted.sublist(encrypted.length - 16));
    final ciphertext = encrypted.sublist(12, encrypted.length - 16);
    final plaintext = await _cipher.decrypt(
      SecretBox(ciphertext, nonce: nonce, mac: mac),
      secretKey: secretKey,
    );
    if (plaintext.length != sticker.sizeBytes ||
        sha256.convert(plaintext).toString() != sticker.sha256) {
      throw const FormatException('Saved sticker does not match its metadata.');
    }
    return Uint8List.fromList(plaintext);
  });

  Future<LocalSticker> addSticker({
    required List<int> bytes,
    required String extension,
    String label = '',
  }) => _serialized(() async {
    final normalizedExtension = extension.toLowerCase().replaceFirst('.', '');
    if (!_extensions.contains(normalizedExtension)) {
      throw ArgumentError.value(
        extension,
        'extension',
        'Unsupported sticker format.',
      );
    }
    if (bytes.isEmpty || bytes.length > maxStickerBytes) {
      throw StateError('Stickers must be nonempty and no larger than 4 MB.');
    }
    final digest = sha256.convert(bytes).toString();
    final directory = await _directory();
    final manifest = await _readManifest();
    final duplicate = manifest.where((item) => item.sha256 == digest);
    if (duplicate.isNotEmpty) return duplicate.first;
    if (manifest.length >= maxStickers) {
      throw StateError('Your sticker pack is full (100 stickers maximum).');
    }
    final totalBytes = manifest.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );
    if (totalBytes + bytes.length > maxPackBytes) {
      throw StateError('Your sticker pack is full (32 MB maximum).');
    }

    final id = _uuid.v4();
    final normalizedLabel = label.trim();
    final sticker = LocalSticker(
      id: id,
      fileName: '$id.enc',
      extension: normalizedExtension,
      label: normalizedLabel.length > 80
          ? normalizedLabel.substring(0, 80)
          : normalizedLabel,
      sizeBytes: bytes.length,
      addedAt: DateTime.now().toUtc(),
      sha256: digest,
    );
    final secretBox = await _cipher.encrypt(bytes, secretKey: await _getKey());
    final encrypted = Uint8List.fromList([
      ...secretBox.nonce,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    final stickerFile = File(
      '${directory.path}${Platform.pathSeparator}${sticker.fileName}',
    );
    try {
      await stickerFile.writeAsBytes(encrypted, flush: true);
      manifest.add(sticker);
      await _writeManifest(manifest);
      return sticker;
    } catch (_) {
      if (await stickerFile.exists()) await stickerFile.delete();
      rethrow;
    } finally {
      encrypted.fillRange(0, encrypted.length, 0);
    }
  });

  Future<void> remove(LocalSticker sticker) => _serialized(() async {
    final directory = await _directory();
    if (sticker.fileName != '${sticker.id}.enc') {
      throw const FormatException('Invalid sticker file path.');
    }
    final manifest = await _readManifest();
    final updated = manifest.where((item) => item.id != sticker.id).toList();
    if (updated.length == manifest.length) return;
    await _writeManifest(updated);
    final file = File(
      '${directory.path}${Platform.pathSeparator}${sticker.fileName}',
    );
    if (await file.exists()) await file.delete();
  });

  Future<SecretKey> _getKey() async {
    final keyName = '$_keyPrefix$_userKey';
    final stored = await _keyStore.read(keyName);
    if (stored != null) {
      final bytes = base64Decode(stored);
      if (bytes.length != 32) {
        throw const FormatException('Saved sticker key is invalid.');
      }
      return SecretKey(bytes);
    }
    final key = await _cipher.newSecretKey();
    final bytes = Uint8List.fromList(await key.extractBytes());
    try {
      await _keyStore.write(keyName, base64Encode(bytes));
      return key;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Directory> _directory() async {
    final root = _rootDirectory ?? await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}chat_stickers'
      '${Platform.pathSeparator}$_userKey',
    );
    await directory.create(recursive: true);
    return directory;
  }

  Future<List<LocalSticker>> _readManifest() async {
    final directory = await _directory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}manifest.json',
    );
    if (!await file.exists()) return [];
    if (await file.length() > _maxManifestBytes) {
      throw const FormatException('Saved sticker pack is too large to load.');
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! List) {
      throw const FormatException('Saved sticker pack is invalid.');
    }
    final stickers = decoded.map((value) {
      if (value is! Map<String, dynamic>) {
        throw const FormatException('Saved sticker metadata is invalid.');
      }
      return LocalSticker.fromJson(value);
    }).toList();
    final totalBytes = stickers.fold<int>(
      0,
      (sum, item) => sum + item.sizeBytes,
    );
    if (stickers.length > maxStickers ||
        totalBytes > maxPackBytes ||
        stickers.any(
          (item) =>
              item.sizeBytes > maxStickerBytes ||
              item.sizeBytes < 1 ||
              !_extensions.contains(item.extension),
        )) {
      throw const FormatException('Saved sticker pack exceeds its limits.');
    }
    return stickers;
  }

  Future<void> _writeManifest(List<LocalSticker> stickers) async {
    final directory = await _directory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}manifest.json',
    );
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode(stickers.map((sticker) => sticker.toJson()).toList()),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = Completer<T>();
    final previous = _queues[_userKey] ?? Future<void>.value();
    final release = Completer<void>();
    final current = release.future;
    _queues[_userKey] = current;
    unawaited(
      previous.then((_) async {
        try {
          result.complete(await operation());
        } catch (error, stackTrace) {
          result.completeError(error, stackTrace);
        } finally {
          release.complete();
          if (identical(_queues[_userKey], current)) _queues.remove(_userKey);
        }
      }),
    );
    return result.future;
  }
}
