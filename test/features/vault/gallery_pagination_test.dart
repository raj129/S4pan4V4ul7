import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/core/session/vault_session.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_photo_repository.dart';
import 'package:photo_vault/core/widgets/app_surfaces.dart';
import 'package:photo_vault/features/vault/application/services/import_manager.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';
import 'package:photo_vault/features/vault/presentation/screens/gallery/gallery_home_screen.dart';

VaultPhoto _photo(int id) => VaultPhoto(
  id: 'photo-$id',
  originalFilename: 'photo-$id.jpg',
  encryptedFilePath: '/tmp/photo-$id.enc',
  thumbnailPath: '/tmp/photo-$id.thumb',
  wrappedDek: 'wrapped',
  photoNonce: 'nonce',
  thumbnailNonce: 'thumb-nonce',
  encryptionVersion: 1,
  checksumSha256: 'checksum-$id',
  fileSize: 100,
  mimeType: 'image/jpeg',
  createdTimeMs: id,
  importedTimeMs: id,
  modifiedTimeMs: id,
  favorite: false,
  isTrashed: false,
);

void main() {
  testWidgets('gallery loads more photos as the grid is scrolled', (
    tester,
  ) async {
    final repository = InMemoryPhotoRepository();
    for (var id = 0; id < 150; id++) {
      await repository.upsertPhoto(_photo(id));
    }
    final importManager = ImportManager(
      photoRepository: repository,
      cryptoService: AesGcmCryptoService(),
      vaultSession: VaultSession(),
    );
    addTearDown(importManager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GalleryHomeScreen(
          mode: UserMode.localOnly,
          photoRepository: repository,
          importManager: importManager,
          photoSyncEnabled: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.widget<MediaGrid>(find.byType(MediaGrid)).itemCount, 100);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final gridController = tester
        .widget<GridView>(find.byType(GridView))
        .controller!;
    gridController.jumpTo(gridController.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    expect(tester.widget<MediaGrid>(find.byType(MediaGrid)).itemCount, 150);
  });
}
