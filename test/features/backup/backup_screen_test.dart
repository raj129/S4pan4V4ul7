import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/core/platform/battery_optimization.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_photo_repository.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/features/backup/application/backup_manager.dart';
import 'package:photo_vault/features/backup/application/vault_photo_backup_service.dart';
import 'package:photo_vault/features/backup/presentation/backup_screen.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/services/chat_backup_service.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/features/vault/application/services/pin_validator.dart';
import 'package:photo_vault/features/vault/application/usecases/unlock_vault_usecase.dart';
import 'package:photo_vault/features/vault/domain/entities/vault_photo.dart';

import '../../helpers/memory_message_cache.dart';

class _NoCrypto implements ChatCryptoService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _FakeUnlock implements UnlockVaultUseCase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _StubChatBackupService extends ChatBackupService {
  _StubChatBackupService({
    this.backupResult,
    this.snapshot,
    this.findFailure,
    this.restoreCount = 0,
  }) : super(
         cache: MemoryMessageCache(),
         crypto: _NoCrypto(),
         stores: const [],
         currentUid: _noUid,
       );

  static String? _noUid() => null;

  final ChatBackupResult? backupResult;
  final ChatBackupSnapshot? snapshot;
  final Object? findFailure;
  final int restoreCount;

  @override
  Future<void> migrateLegacyWifiSetting() async {}

  @override
  Future<DateTime?> lastBackupAt() async => null;

  @override
  Future<ChatBackupResult> backupNow({bool interactive = false}) async {
    final result = backupResult;
    if (result == null) throw StateError('No backup result configured');
    return result;
  }

  @override
  Future<ChatBackupSnapshot?> findLatestBackup({
    bool interactive = false,
    bool? cloudOnly,
    bool ignoreCloudSetting = false,
    void Function(ChatRestoreProgress)? onProgress,
  }) async {
    final failure = findFailure;
    if (failure != null) throw failure;
    return snapshot;
  }

  @override
  Future<int> restore(
    ChatBackupSnapshot snapshot, {
    void Function(ChatRestoreProgress)? onProgress,
  }) async => restoreCount;
}

class _StubPhotoBackupService extends VaultPhotoBackupService {
  _StubPhotoBackupService({this.backupResult, this.restoreResult})
    : super(
        stores: const [],
        photoRepository: InMemoryPhotoRepository(),
        listPhotos: () async => const [],
        crypto: _NoCrypto(),
        settings: InMemorySettingsRepository(),
        currentUid: _noUid,
        networkAllowed: _networkAllowed,
        currentVaultId: _vaultId,
      );

  static String? _noUid() => null;
  static Future<bool> _networkAllowed() async => true;
  static Future<String?> _vaultId() async => 'vault-1';

  final VaultPhotoBackupResult? backupResult;
  final VaultPhotoRestoreResult? restoreResult;

  @override
  Future<VaultPhotoBackupResult> backup({
    bool interactive = false,
    DateTime? deadline,
  }) async {
    final result = backupResult;
    if (result == null) throw StateError('No backup result configured');
    return result;
  }

  @override
  Future<VaultPhotoRestoreResult> restore({
    bool interactive = false,
    bool includeCloud = false,
  }) async {
    return restoreResult ??
        const VaultPhotoRestoreResult(
          restored: 0,
          alreadyPresent: 0,
          unavailable: 0,
        );
  }
}

class _FakeAuth implements AuthRepository {
  _FakeAuth({this.signedIn = true, this.warmUpFailure});

  bool signedIn;
  Object? warmUpFailure;
  int warmUpCalls = 0;

  @override
  Future<bool> isSignedIn() async => signedIn;

  @override
  Future<AuthResult> signInWithGoogle() async {
    signedIn = true;
    return const AuthResult(userId: 'u1', email: 'u1@example.com');
  }

  @override
  Future<void> warmUpDriveAuthorization({bool interactive = false}) async {
    warmUpCalls++;
    final err = warmUpFailure;
    if (err != null) throw err;
  }

  @override
  Future<http.Client?> getAuthenticatedClient({
    bool interactive = false,
  }) async => null;

  @override
  Future<void> signOut() async {
    signedIn = false;
  }
}

class _FakeBattery implements BatteryOptimization {
  _FakeBattery({required this.exempt});

  bool exempt;

  @override
  Future<bool> isExempt() async => exempt;

  @override
  Future<bool> requestExemption() async {
    exempt = true;
    return true;
  }
}

class _DelayedPhotoBackupService extends _StubPhotoBackupService {
  _DelayedPhotoBackupService(this.completer);

  final Completer<VaultPhotoBackupResult> completer;

  @override
  Future<VaultPhotoBackupResult> backup({
    bool interactive = false,
    DateTime? deadline,
  }) => completer.future;
}

void main() {
  late InMemorySettingsRepository settings;

  Future<void> pump(
    WidgetTester tester, {
    Future<List<VaultPhoto>> Function()? listPhotos,
    ChatBackupService? Function()? chatBackup,
    VaultPhotoBackupService? vaultPhotoBackup,
    AuthRepository? authRepository,
    BackupManager? backupManager,
    BatteryOptimization? batteryOptimization,
  }) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    settings = InMemorySettingsRepository();
    final photoBackup = VaultPhotoBackupService(
      stores: const [],
      photoRepository: InMemoryPhotoRepository(),
      listPhotos: listPhotos ?? () async => const [],
      crypto: _NoCrypto(),
      settings: settings,
      currentUid: () => null,
      networkAllowed: () async => true,
      currentVaultId: () async => 'vault-1',
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => context.push('/settings/backup'),
                child: const Text('Open backup'),
              ),
            ),
          ),
          routes: [
            GoRoute(
              path: 'settings/backup',
              builder: (context, state) => BackupScreen(
                settingsRepository: settings,
                chatBackup: chatBackup ?? () => null,
                vaultPhotoBackup: () => vaultPhotoBackup ?? photoBackup,
                unlockVaultUseCase: _FakeUnlock(),
                pinValidator: PinValidator(),
                authRepository: authRepository,
                backupManager: backupManager,
                batteryOptimization:
                    batteryOptimization ?? _FakeBattery(exempt: true),
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open backup'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'a very long error stays bounded and leaving the screen is safe',
    (tester) async {
      final huge = 'x' * 20000;
      await pump(tester, listPhotos: () async => throw Exception(huge));

      await tester.tap(find.text('Back up now'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final message = tester.widget<Text>(find.textContaining('Failed:')).data!;
      expect(message.length, lessThan(300));

      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Open backup'), findsOneWidget);
    },
  );

  Finder switchTile(String title) => find.ancestor(
    of: find.text(title),
    matching: find.byType(SwitchListTile),
  );

  testWidgets('shows every backup choice in one place', (tester) async {
    await pump(tester);

    expect(find.text('What to back up'), findsOneWidget);
    expect(find.text('Where to back up'), findsOneWidget);
    expect(find.text('Chats'), findsOneWidget);
    expect(find.text('Vault photos'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    expect(find.text('Google Drive'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Delete backup'), 200);
    expect(find.text('Restore from backup'), findsOneWidget);
    expect(find.text('Recover a Google vault'), findsOneWidget);
    expect(find.text('Delete backup'), findsOneWidget);
  });

  testWidgets('turning off Google Drive persists and disables Wi-Fi only', (
    tester,
  ) async {
    await pump(tester);
    expect(
      tester.widget<SwitchListTile>(switchTile('Wi-Fi only')).onChanged,
      isNull,
    );

    await tester.tap(switchTile('Google Drive'));
    await tester.pumpAndSettle();
    expect(await settings.isBackupCloudEnabled(), isTrue);
    expect(
      tester.widget<SwitchListTile>(switchTile('Wi-Fi only')).onChanged,
      isNotNull,
    );

    await tester.tap(switchTile('Google Drive'));
    await tester.pumpAndSettle();

    expect(await settings.isBackupCloudEnabled(), isFalse);
    expect(
      tester.widget<SwitchListTile>(switchTile('Wi-Fi only')).onChanged,
      isNull,
    );
  });

  testWidgets('turning off chats persists the choice', (tester) async {
    await pump(tester);

    await tester.tap(switchTile('Chats'));
    await tester.pumpAndSettle();

    expect(await settings.isBackupChatsEnabled(), isFalse);
  });

  testWidgets('a failing chat part is reported without skipping vault photos', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();

    final message = tester.widget<Text>(find.textContaining('Failed:')).data!;
    expect(message, contains('chats unavailable'));
    expect(message, contains('vault photos:'));
  });

  testWidgets('backup summary identifies the successful destination', (
    tester,
  ) async {
    final longError = List.filled(500, 'x').join();
    final chat = _StubChatBackupService(
      backupResult: ChatBackupResult(
        backupAt: DateTime.utc(2024),
        messageCount: 3,
        savedTo: const ['This device'],
        skipped: {
          'Google Drive':
              'DetailedApiRequestError(status: 403, message: '
              'Google Drive API has not been used in project $longError)',
        },
      ),
    );
    final photos = _StubPhotoBackupService(
      backupResult: const VaultPhotoBackupResult(
        photoCount: 0,
        missingCount: 0,
        savedTo: [],
        skipped: {},
      ),
    );
    await pump(tester, chatBackup: () => chat, vaultPhotoBackup: photos);

    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();

    final message = tester.widget<Text>(find.textContaining('Backed up')).data!;
    expect(message, contains('3 chat messages to This device'));
    expect(message, contains('Google Drive API is disabled'));
    expect(message, contains('Enable drive.googleapis.com'));
    expect(message.length, lessThan(350));
    expect(message, contains('No vault photos were available to back up'));
  });

  testWidgets(
    'photo restore runs and reports partial results after chat fails',
    (tester) async {
      final chat = _StubChatBackupService(
        findFailure: StateError('device copy is unreadable'),
      );
      final photos = _StubPhotoBackupService(
        restoreResult: const VaultPhotoRestoreResult(
          restored: 1,
          alreadyPresent: 2,
          unavailable: 1,
          foundBackup: true,
          failures: ['This device: read failed'],
        ),
      );
      await pump(tester, chatBackup: () => chat, vaultPhotoBackup: photos);

      await tester.scrollUntilVisible(find.text('Restore from backup'), 200);
      await tester.tap(find.text('Restore from backup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore'));
      await tester.pumpAndSettle();

      final message = tester
          .widget<Text>(find.textContaining('Restored'))
          .data!;
      expect(message, contains('1 vault photo'));
      expect(message, contains('chats:'));
      expect(message, contains('2 vault photos were already on this device'));
      expect(message, contains('1 vault photo could not be recovered'));
      expect(message, contains('This device: read failed'));
    },
  );

  testWidgets('restore message uses the imported count and backup source', (
    tester,
  ) async {
    final record = CachedMessageRecord(
      messageId: 'message-1',
      threadId: 'thread-1',
      senderId: 'user-1',
      encryptedText: 'ciphertext',
      sentAtMs: 1,
      payloadJson: '{}',
    );
    final chat = _StubChatBackupService(
      snapshot: ChatBackupSnapshot(
        backupAt: DateTime.utc(2024),
        source: 'This device',
        messages: [record, record],
        clearedBefore: const {},
      ),
      restoreCount: 1,
    );
    await pump(
      tester,
      chatBackup: () => chat,
      vaultPhotoBackup: _StubPhotoBackupService(),
    );

    await tester.scrollUntilVisible(find.text('Restore from backup'), 200);
    await tester.tap(find.text('Restore from backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Restored 1 chat message from This device'),
      findsOneWidget,
    );
  });

  testWidgets('restore distinguishes unreadable backup from no backup', (
    tester,
  ) async {
    final chat = _StubChatBackupService(
      findFailure: StateError('Google Drive returned 403'),
    );
    await pump(
      tester,
      chatBackup: () => chat,
      vaultPhotoBackup: _StubPhotoBackupService(),
    );

    await tester.scrollUntilVisible(find.text('Restore from backup'), 200);
    await tester.tap(find.text('Restore from backup'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    final message = tester
        .widget<Text>(find.textContaining('Could not restore'))
        .data!;
    expect(message, contains('Google Drive returned 403'));
    expect(message, isNot(contains('No backup found')));
  });

  testWidgets('back up now is refused when nothing is selected', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(switchTile('Chats'));
    await tester.tap(switchTile('Vault photos'));
    await tester.tap(switchTile('App settings'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Back up now'), -200);
    await tester.tap(find.text('Back up now'));
    await tester.pumpAndSettle();

    expect(
      find.text('Turn on chats, vault photos, or settings to back up.'),
      findsOneWidget,
    );
  });

  testWidgets('delete asks which copy to remove and warns it is permanent', (
    tester,
  ) async {
    await pump(tester);

    await tester.scrollUntilVisible(find.text('Delete backup'), 200);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete backup'));
    await tester.pumpAndSettle();

    expect(find.text('Delete backup?'), findsOneWidget);
    expect(find.textContaining('cannot be undone'), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('Google Drive'), findsWidgets);
    expect(find.text('Both'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Delete backup?'), findsNothing);
  });

  testWidgets(
    'enabling Google Drive warms up Drive OAuth and reverts on failure',
    (tester) async {
      final auth = _FakeAuth(
        signedIn: true,
        warmUpFailure: const AuthException(
          'Google Drive access was cancelled.',
        ),
      );
      await pump(tester, authRepository: auth);

      await tester.tap(switchTile('Google Drive'));
      await tester.pumpAndSettle();

      expect(auth.warmUpCalls, 1);
      expect(await settings.isBackupCloudEnabled(), isFalse);
      expect(
        find.textContaining('Google Drive access was cancelled.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'backup continues in background via BackupManager across route pop and re-entry',
    (tester) async {
      final completer = Completer<VaultPhotoBackupResult>();
      final delayedPhotos = _DelayedPhotoBackupService(completer);
      final sharedSettings = InMemorySettingsRepository();
      await sharedSettings.setBackupChatsEnabled(false);
      final manager = BackupManager(
        settingsRepository: sharedSettings,
        chatBackup: () => null,
        vaultPhotoBackup: () => delayedPhotos,
      );
      addTearDown(manager.dispose);

      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => context.push('/settings/backup'),
                  child: const Text('Open backup'),
                ),
              ),
            ),
            routes: [
              GoRoute(
                path: 'settings/backup',
                builder: (context, state) => BackupScreen(
                  settingsRepository: sharedSettings,
                  chatBackup: () => null,
                  vaultPhotoBackup: () => delayedPhotos,
                  unlockVaultUseCase: _FakeUnlock(),
                  pinValidator: PinValidator(),
                  backupManager: manager,
                  batteryOptimization: _FakeBattery(exempt: true),
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open backup'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Back up now'));
      await tester.pump();
      expect(manager.isBusy, isTrue);

      // Pop BackupScreen while backup is still running in the background.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(manager.isBusy, isTrue);

      completer.complete(
        const VaultPhotoBackupResult(
          photoCount: 4,
          missingCount: 0,
          savedTo: ['This device'],
          skipped: {},
        ),
      );
      await tester.pumpAndSettle();
      expect(manager.isBusy, isFalse);

      // Reopen BackupScreen: the completed result is shown cleanly.
      await tester.tap(find.text('Open backup'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Backed up 4 vault photos to This device.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('shows battery restriction warning banner when not exempt', (
    tester,
  ) async {
    await pump(tester, batteryOptimization: _FakeBattery(exempt: false));
    expect(
      find.byKey(const Key('backup-battery-warning-banner')),
      findsOneWidget,
    );
  });
}
