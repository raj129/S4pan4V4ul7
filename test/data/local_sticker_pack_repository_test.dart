import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/data/repositories/local_sticker_pack_repository.dart';

class _MemoryStickerKeyStore implements StickerKeyStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  late Directory root;
  late _MemoryStickerKeyStore keyStore;
  late LocalStickerPackRepository repository;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('local-sticker-pack-test-');
    keyStore = _MemoryStickerKeyStore();
    repository = LocalStickerPackRepository(
      userId: 'test-user',
      rootDirectory: root,
      keyStore: keyStore,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('stores sticker bytes encrypted and reads them back', () async {
    final original = [0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 2, 3];
    final sticker = await repository.addSticker(
      bytes: original,
      extension: 'gif',
      label: 'wave',
    );

    final stored = await repository.list();
    expect(stored, hasLength(1));
    expect(stored.single.label, 'wave');
    expect(await repository.readBytes(sticker), orderedEquals(original));

    final encryptedFiles = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.enc'))
        .toList();
    expect(encryptedFiles, hasLength(1));
    expect(
      await encryptedFiles.single.readAsBytes(),
      isNot(orderedEquals(original)),
    );
    expect(keyStore.values, hasLength(1));
  });

  test(
    'deduplicates identical bytes and enforces the sticker size limit',
    () async {
      final first = await repository.addSticker(
        bytes: [1, 2, 3],
        extension: 'png',
      );
      final duplicate = await repository.addSticker(
        bytes: [1, 2, 3],
        extension: 'png',
      );

      expect(duplicate.id, first.id);
      expect(await repository.list(), hasLength(1));
      await expectLater(
        repository.addSticker(
          bytes: List<int>.filled(
            LocalStickerPackRepository.maxStickerBytes + 1,
            1,
          ),
          extension: 'gif',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'serializes writes across repository instances for the same account',
    () async {
      final secondRepository = LocalStickerPackRepository(
        userId: 'test-user',
        rootDirectory: root,
        keyStore: keyStore,
      );
      await Future.wait([
        repository.addSticker(bytes: [1, 2, 3], extension: 'gif'),
        secondRepository.addSticker(bytes: [4, 5, 6], extension: 'png'),
      ]);

      expect(await repository.list(), hasLength(2));
    },
  );
}
