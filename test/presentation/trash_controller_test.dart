import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/import_manager.dart';
import 'package:photo_vault/application/services/vault_session.dart';
import 'package:photo_vault/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/domain/entities/vault_photo.dart';
import 'package:photo_vault/presentation/state/trash/trash_controller.dart';
import 'package:photo_vault/test_helpers/repositories/in_memory_photo_repository.dart';

VaultPhoto _photo(String id, {bool isTrashed = true}) => VaultPhoto(
      id: id,
      originalFilename: '$id.jpg',
      encryptedFilePath: '/tmp/$id.enc',
      thumbnailPath: '/tmp/$id.thumb',
      wrappedDek: 'wrapped',
      photoNonce: 'nonce',
      thumbnailNonce: 'thumb-nonce',
      encryptionVersion: 1,
      checksumSha256: 'checksum-$id',
      fileSize: 100,
      mimeType: 'image/jpeg',
      createdTimeMs: 0,
      importedTimeMs: 0,
      modifiedTimeMs: 0,
      favorite: false,
      isTrashed: isTrashed,
    );

void main() {
  late InMemoryPhotoRepository photoRepository;
  late ImportManager importManager;
  late TrashController controller;

  setUp(() async {
    photoRepository = InMemoryPhotoRepository();
    importManager = ImportManager(
      photoRepository: photoRepository,
      cryptoService: AesGcmCryptoService(),
      vaultSession: VaultSession(),
    );
    await photoRepository.upsertPhoto(_photo('a'));
    await photoRepository.upsertPhoto(_photo('b'));
    controller = TrashController(
      photoRepository: photoRepository,
      importManager: importManager,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  group('TrashController', () {
    test('load() populates photos from the repository', () async {
      await controller.load();
      expect(controller.photos.map((p) => p.id), containsAll(['a', 'b']));
      expect(controller.isLoading, isFalse);
    });

    test('toggleSelection() enters and exits selection mode', () async {
      await controller.load();
      expect(controller.isSelectionMode, isFalse);

      controller.toggleSelection('a');
      expect(controller.isSelectionMode, isTrue);
      expect(controller.selectedIds, {'a'});

      controller.toggleSelection('a');
      expect(controller.isSelectionMode, isFalse);
      expect(controller.selectedIds, isEmpty);
    });

    test('restoreSelected() moves selected photos out of trash', () async {
      await controller.load();
      controller.toggleSelection('a');

      final restoredCount = await controller.restoreSelected();

      expect(restoredCount, 1);
      expect(controller.isSelectionMode, isFalse);
      final restored = await photoRepository.getPhotoById('a');
      expect(restored!.isTrashed, isFalse);
    });

    test(
      'permanentlyDeleteSelected() removes photos and reloads the list',
      () async {
        await controller.load();
        controller.toggleSelection('a');

        final deletedCount = await controller.permanentlyDeleteSelected();

        expect(deletedCount, 1);
        expect(await photoRepository.getPhotoById('a'), isNull);
        expect(controller.photos.map((p) => p.id), ['b']);
      },
    );

    test('emptyBin() permanently deletes every trashed photo', () async {
      await controller.load();

      await controller.emptyBin();

      expect(controller.photos, isEmpty);
      expect(await photoRepository.getPhotoById('a'), isNull);
      expect(await photoRepository.getPhotoById('b'), isNull);
    });

    test('restore() moves a single photo out of trash', () async {
      await controller.load();
      final photo = controller.photos.first;

      await controller.restore(photo);

      final restored = await photoRepository.getPhotoById(photo.id);
      expect(restored!.isTrashed, isFalse);
    });
  });
}
