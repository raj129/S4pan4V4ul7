import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:photo_vault/core/integrations/chat_attachment_vault_importer.dart';
import 'package:photo_vault/core/integrations/chat_vault_bridge.dart';
import 'package:photo_vault/features/vault/application/services/import_manager.dart';
import 'package:photo_vault/core/session/vault_session.dart';
import 'package:photo_vault/features/vault/application/usecases/export_photo_usecase.dart';
import 'package:photo_vault/core/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_photo_repository.dart';
import 'package:uuid/uuid.dart';

class FailingRepository extends InMemoryPhotoRepository {
  bool fail = false;
  bool throwAfterCommit = false;

  @override
  Future<void> upsertPhoto(VaultPhoto photo) async {
    if (fail) throw StateError('Database unavailable');
    await super.upsertPhoto(photo);
    if (throwAfterCommit) throw StateError('Ambiguous commit');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory directory;
  late FailingRepository repository;
  late VaultSession session;
  late ImportManager manager;
  late ChatVaultBridge bridge;
  final document = Uint8List.fromList(
    utf8.encode('%PDF-1.7\nreceived document'),
  );

  ChatVaultBridge createBridge() {
    final crypto = AesGcmCryptoService();
    manager =
        ImportManager(
          photoRepository: repository,
          cryptoService: crypto,
          vaultSession: session,
        )..configureStorage(
          useExternalStorageMirror: true,
          driveEncryptedBackupEnabled: false,
        );
    return ChatVaultBridge(
      photoRepository: repository,
      importManager: manager,
      exportPhoto: ExportPhotoUseCase(
        cryptoService: crypto,
        vaultSession: session,
      ),
    );
  }

  setUp(() async {
    directory = Directory('.test_chat_vault_${const Uuid().v4()}').absolute;
    await directory.create();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => directory.path);
    repository = FailingRepository();
    session = VaultSession()
      ..unlock(vaultId: 'vault-a', vmkBytes: List.filled(32, 8));
    bridge = createBridge();
  });

  tearDown(() async {
    manager.dispose();
    session.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  test('locked imports fail without source cleanup or files', () async {
    session.lock();
    var cleanup = false;
    await expectLater(
      bridge.moveToVault(
        bytes: document,
        filename: 'document.pdf',
        sourceId: 'alice/thread/ref',
        onMarkMoved: () async {},
        onSourceCleanup: () async {
          cleanup = true;
        },
      ),
      throwsA(isA<VaultLockedException>()),
    );
    expect(cleanup, isFalse);
    expect(directory.listSync(recursive: true), isEmpty);
  });

  test(
    'generic document import returns identity, encrypts bytes, hides from gallery',
    () async {
      final events = <String>[];
      final result = await bridge.moveToVault(
        bytes: document,
        filename: 'document.pdf',
        sourceId: 'alice/thread/ref',
        mediaType: 'document',
        mimeType: 'image/png',
        onMarkMoved: () async {
          events.add('marked');
        },
        onSourceCleanup: () async {
          events.add('cleanup');
        },
      );
      expect(result.cleanupPending, isFalse);
      expect(events, ['marked', 'cleanup']);
      expect(result.item.mimeType, 'application/pdf');
      expect(await bridge.readVaultPhoto(result.item), document);
      expect(await repository.listGalleryPage(page: 0, pageSize: 50), isEmpty);
      expect(await bridge.listSavedAttachments(), hasLength(1));
      final encrypted = await File(
        result.item.encryptedFilePath,
      ).readAsString();
      expect(encrypted, isNot(contains('received document')));
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.pdf')),
        isEmpty,
      );
      final journal = await manager.readChatMove('alice/thread/ref');
      expect(journal!['phase'], 'complete');
    },
  );

  test('images decode in memory and remain visible in gallery', () async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    final result = await bridge.moveToVault(
      bytes: bytes,
      filename: 'picture.txt',
      sourceId: 'alice/thread/image',
    );
    expect(result.item.mimeType, 'image/png');
    expect(
      await repository.listGalleryPage(page: 0, pageSize: 50),
      hasLength(1),
    );
    expect(await bridge.thumbnailOf(result.item), isNotNull);
  });

  test(
    'corrupt images and malicious filenames are not successful imports',
    () async {
      for (final filename in [
        '../escape.pdf',
        r'..\escape.pdf',
        '/absolute',
        'C:bad',
        'x\u0000.pdf',
      ]) {
        await expectLater(
          bridge.moveToVault(
            bytes: document,
            filename: filename,
            sourceId: 'alice/thread/$filename',
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        bridge.moveToVault(
          bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
          filename: 'broken.png',
          sourceId: 'alice/thread/bad',
          mediaType: 'image',
        ),
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        bridge.moveToVault(
          bytes: Uint8List.fromList([1, 2, 3]),
          filename: 'bad.jpg',
          sourceId: 'alice/thread/bad2',
          mediaType: 'image',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(await repository.listAttachments(), isEmpty);
    },
  );

  test('video, audio, arbitrary bytes do not require image decoding', () async {
    for (final entry in {
      'clip.mp4': Uint8List.fromList([
        0,
        0,
        0,
        20,
        ...utf8.encode('ftypisom'),
        1,
      ]),
      'sound.mp3': Uint8List.fromList([...utf8.encode('ID3'), 1, 2, 3]),
      'archive.bin': Uint8List.fromList([1, 7, 9, 4]),
    }.entries) {
      final result = await bridge.moveToVault(
        bytes: entry.value,
        filename: entry.key,
        sourceId: 'alice/thread/${entry.key}',
      );
      expect(result.item.mimeType.startsWith('image/'), isFalse);
      expect(await bridge.readVaultPhoto(result.item), entry.value);
    }
    expect(await repository.listGalleryPage(page: 0, pageSize: 50), isEmpty);
  });

  test('duplicate checksum returns original identity before cleanup', () async {
    final first = await bridge.moveToVault(
      bytes: document,
      filename: 'first.pdf',
      sourceId: 'alice/thread/first',
    );
    var cleaned = false;
    final second = await bridge.moveToVault(
      bytes: document,
      filename: 'second.pdf',
      sourceId: 'alice/thread/second',
      onMarkMoved: () async {},
      onSourceCleanup: () async {
        expect(await repository.getPhotoById(first.item.id), isNotNull);
        cleaned = true;
      },
    );
    expect(second.item.id, first.item.id);
    expect(second.deduplicated, isTrue);
    expect(cleaned, isTrue);
    expect(await repository.listAttachments(), hasLength(1));
  });

  test('existing gallery checksum is a successful direct duplicate', () async {
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: 2, height: 2)),
    );
    final source = File(
      '${directory.path}${Platform.pathSeparator}original.png',
    );
    await source.writeAsBytes(bytes);
    await manager.enqueueImport(files: [XFile(source.path)], source: 'gallery');
    final original = (await repository.listGalleryPage(
      page: 0,
      pageSize: 20,
    )).single;
    var cleaned = false;
    final result = await bridge.moveToVault(
      bytes: bytes,
      filename: 'received.png',
      sourceId: 'alice/thread/ref',
      onMarkMoved: () async {},
      onSourceCleanup: () async {
        cleaned = true;
      },
    );
    expect(result.item.id, original.id);
    expect(result.deduplicated, isTrue);
    expect(cleaned, isTrue);
    expect(await source.readAsBytes(), bytes);
  });

  test(
    'mirror failure is not success and leaves no committed attachment',
    () async {
      final vault = Directory(
        '${directory.path}${Platform.pathSeparator}vault',
      );
      await vault.create();
      await File(
        '${vault.path}${Platform.pathSeparator}manifest',
      ).writeAsString('block');
      var cleaned = false;
      await expectLater(
        bridge.moveToVault(
          bytes: document,
          filename: 'document.pdf',
          sourceId: 'alice/thread/ref',
          onMarkMoved: () async {},
          onSourceCleanup: () async {
            cleaned = true;
          },
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(cleaned, isFalse);
      expect(await repository.listAttachments(), isEmpty);
    },
  );

  test('marker failure never invokes source cleanup', () async {
    var cleaned = false;
    final result = await bridge.moveToVault(
      bytes: document,
      filename: 'document.pdf',
      sourceId: 'alice/thread/ref',
      onMarkMoved: () async {
        throw StateError('Marker write failed');
      },
      onSourceCleanup: () async {
        cleaned = true;
      },
    );
    expect(result.cleanupPending, isTrue);
    expect(result.cleanupError, isNotNull);
    expect(cleaned, isFalse);
    expect(await bridge.readVaultPhoto(result.item), document);
  });

  test(
    'failed repository commit propagates and keeps source; next move works',
    () async {
      repository.fail = true;
      var cleaned = false;
      await expectLater(
        bridge.moveToVault(
          bytes: document,
          filename: 'document.pdf',
          sourceId: 'alice/thread/ref',
          onMarkMoved: () async {},
          onSourceCleanup: () async {
            cleaned = true;
          },
        ),
        throwsStateError,
      );
      expect(cleaned, isFalse);
      expect(await repository.listAttachments(), isEmpty);
      expect(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (f) =>
                  f.path.endsWith('.photo.enc') ||
                  f.path.endsWith('.thumb.enc'),
            ),
        isEmpty,
      );
      repository.fail = false;
      expect(
        (await bridge.moveToVault(
          bytes: document,
          filename: 'document.pdf',
          sourceId: 'alice/thread/ref',
        )).item.id,
        isNotEmpty,
      );
    },
  );

  test(
    'restart resumes committed cleanup without source bytes or second import',
    () async {
      final first = await bridge.moveToVault(
        bytes: document,
        filename: 'document.pdf',
        sourceId: 'alice/thread/ref',
        onMarkMoved: () async {},
        onSourceCleanup: () async {
          throw StateError('Interrupted');
        },
      );
      expect(first.cleanupPending, isTrue);
      expect(first.cleanupError, isNotNull);
      manager.dispose();
      bridge = createBridge();
      final resumed = await bridge.resumeMove(
        sourceId: 'alice/thread/ref',
        onMarkMoved: () async {},
        onSourceCleanup: () async {},
      );
      expect(resumed!.item.id, first.item.id);
      expect(resumed.cleanupPending, isFalse);
      expect(await repository.listAttachments(), hasLength(1));
    },
  );

  test(
    'restart reconciles ambiguous repository commit from importing journal',
    () async {
      repository.throwAfterCommit = true;
      await expectLater(
        bridge.moveToVault(
          bytes: document,
          filename: 'document.pdf',
          sourceId: 'alice/thread/ref',
        ),
        throwsStateError,
      );
      repository.throwAfterCommit = false;
      final resumed = await bridge.resumeMove(
        sourceId: 'alice/thread/ref',
        onMarkMoved: () async {},
        onSourceCleanup: () async {},
      );
      expect(resumed!.cleanupPending, isFalse);
      expect(await repository.listAttachments(), hasLength(1));
    },
  );

  test('corrupt existing duplicate is never accepted or cleaned', () async {
    final first = await bridge.moveToVault(
      bytes: document,
      filename: 'document.pdf',
      sourceId: 'alice/thread/first',
    );
    await File(first.item.encryptedFilePath).writeAsString('{}');
    var cleaned = false;
    await expectLater(
      bridge.moveToVault(
        bytes: document,
        filename: 'document.pdf',
        sourceId: 'alice/thread/second',
        onMarkMoved: () async {},
        onSourceCleanup: () async {
          cleaned = true;
        },
      ),
      throwsA(anything),
    );
    expect(cleaned, isFalse);
  });

  test('source identity mismatch and oversized/empty inputs fail', () async {
    await bridge.moveToVault(
      bytes: document,
      filename: 'document.pdf',
      sourceId: 'alice/thread/ref',
    );
    await expectLater(
      bridge.moveToVault(
        bytes: Uint8List.fromList([4]),
        filename: 'other.bin',
        sourceId: 'alice/thread/ref',
      ),
      throwsStateError,
    );
    await expectLater(
      bridge.moveToVault(
        bytes: Uint8List(0),
        filename: 'empty.bin',
        sourceId: 'alice/thread/empty',
      ),
      throwsArgumentError,
    );
    await expectLater(
      bridge.moveToVault(
        bytes: Uint8List(ChatAttachmentVaultImporter.maxAttachmentBytes + 1),
        filename: 'large.bin',
        sourceId: 'alice/thread/large',
      ),
      throwsArgumentError,
    );
    expect(
      sha256.convert(document).toString(),
      (await repository.listAttachments()).single.checksumSha256,
    );
  });
}
