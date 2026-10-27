import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_photo_repository.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';

VaultPhoto _photo(String id, int importedAt) => VaultPhoto(
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
  createdTimeMs: importedAt,
  importedTimeMs: importedAt,
  modifiedTimeMs: importedAt,
  favorite: false,
  isTrashed: false,
);

void main() {
  test(
    'gallery paging supports a moving offset after inserts and deletes',
    () async {
      final repository = InMemoryPhotoRepository();
      for (var i = 1; i <= 5; i++) {
        await repository.upsertPhoto(_photo('photo-$i', i));
      }

      final first = await repository.listGalleryPage(page: 0, pageSize: 2);
      final second = await repository.listGalleryPage(
        page: 0,
        pageSize: 2,
        offset: first.length,
      );

      expect(first.map((photo) => photo.id), ['photo-5', 'photo-4']);
      expect(second.map((photo) => photo.id), ['photo-3', 'photo-2']);
    },
  );
}
