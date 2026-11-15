import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:photo_vault/core/crypto/services/aes_gcm_crypto_service.dart';
import 'package:photo_vault/core/session/vault_session.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_photo_repository.dart';
import 'package:photo_vault/core/widgets/main_scaffold_scope.dart';
import 'package:photo_vault/features/vault/application/services/import_manager.dart';
import 'package:photo_vault/features/vault/domain/entities/user_mode.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';
import 'package:photo_vault/features/vault/presentation/screens/gallery/gallery_home_screen.dart';
import 'package:photo_vault/features/vault/presentation/screens/import/import_screen.dart';
import 'package:photo_vault/features/vault/presentation/widgets/confirm_dialog.dart';

VaultPhoto _testPhoto(int id) => VaultPhoto(
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
  testWidgets('confirm dialog separates buttons and applies destructive styling', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showConfirmDialog(
                  context,
                  title: 'Delete 3 photos?',
                  content: 'These photos will be moved to Secure Trash.',
                  confirmLabel: 'Delete',
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('Delete 3 photos?'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);

    final filledBtn = tester.widget<FilledButton>(find.byType(FilledButton));
    final errorColor = Theme.of(tester.element(find.byType(FilledButton))).colorScheme.error;
    expect(filledBtn.style?.backgroundColor?.resolve({}), errorColor);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('gallery tile has no delete button and steady sync bar is hidden when idle', (
    tester,
  ) async {
    final repository = InMemoryPhotoRepository();
    await repository.upsertPhoto(_testPhoto(1));
    final importManager = ImportManager(
      photoRepository: repository,
      cryptoService: AesGcmCryptoService(),
      vaultSession: VaultSession(),
    );
    addTearDown(importManager.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: GalleryHomeScreen(
          mode: UserMode.googleEnabled,
          photoRepository: repository,
          importManager: importManager,
          photoSyncEnabled: true,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Gallery quick lock button is present
    expect(find.byType(QuickLockActionButton), findsOneWidget);

    // Delete icon button on thumbnail is removed
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    // Steady "Sync is running in background" text is NOT shown while idle
    expect(find.text('Sync is running in background'), findsNothing);
  });

  testWidgets('QuickLockActionButton triggers lockApp callback', (tester) async {
    var locked = false;
    await tester.pumpWidget(
      MaterialApp(
        home: VaultLockScope(
          onLock: () => locked = true,
          child: const Scaffold(
            appBar: PreferredSize(
              preferredSize: Size.fromHeight(56),
              child: QuickLockActionButton(),
            ),
          ),
        ),
      ),
    );

    expect(locked, isFalse);
    await tester.tap(find.byType(QuickLockActionButton));
    expect(locked, isTrue);
  });

  testWidgets('share-intent import screen shows Send in chat and Save to vault buttons with icons', (
    tester,
  ) async {
    final repository = InMemoryPhotoRepository();
    final importManager = ImportManager(
      photoRepository: repository,
      cryptoService: AesGcmCryptoService(),
      vaultSession: VaultSession(),
    );
    addTearDown(importManager.dispose);

    importManager.setPendingShareFiles([XFile('/tmp/shared.jpg')]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportScreen(
            importManager: importManager,
            onImportQueued: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Send in chat'), findsOneWidget);
    expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsOneWidget);
    expect(find.text('Save to vault'), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
  });
}
