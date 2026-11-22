import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_loader.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_manager_service.dart';
import 'package:photo_vault/features/chat/application/services/profile_service.dart';
import 'package:photo_vault/features/chat/data/repositories/firebase_avatar_storage.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_user.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/user_repository.dart';
import 'package:photo_vault/features/chat/presentation/screens/profile_screen.dart';
import 'package:photo_vault/core/presentation/theme/app_theme.dart';

class _Store extends NoopMessageCacheRepository {
  final values = <String, String>{};

  @override
  Future<String?> readSetting(String key) async => values[key];

  @override
  Future<void> writeSetting(String key, String? value) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }
}

class _Users implements UserRepository {
  bool fail = false;
  final upserts = <ChatUser>[];

  @override
  Future<void> upsertProfile(
    ChatUser user, {
    bool includeProfile = true,
  }) async {
    if (fail) throw Exception('offline');
    upserts.add(user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Avatars implements AvatarStorage {
  @override
  Future<String> upload(String uid, dynamic bytes) async => 'https://x/y';

  @override
  Future<void> delete(String uid) async {}
}

class _UnusedMedia implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _UnusedMessages implements MessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final me = ChatUser(
    uid: 'me',
    email: 'me@example.com',
    displayName: 'Me',
    publicKey: '',
    createdAt: DateTime.utc(2024),
  );

  Future<(ProfileService, _Users)> pump(
    WidgetTester tester, {
    ChatMediaLoader? mediaLoader,
    ChatMediaManagerService? mediaManagerService,
  }) async {
    final users = _Users();
    final service = ProfileService(
      store: _Store(),
      userRepository: users,
      avatarStorage: _Avatars(),
    );
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (c, _) => Scaffold(
            body: TextButton(
              onPressed: () => c.push('/profile'),
              child: const Text('chat list'),
            ),
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (_, _) => ProfileScreen(
            me: me,
            service: service,
            mediaLoader: mediaLoader,
            mediaManagerService: mediaManagerService,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(theme: AppTheme.light, routerConfig: router),
    );
    await tester.tap(find.text('chat list'));
    await tester.pumpAndSettle();
    return (service, users);
  }

  testWidgets('profile edits name via dialog and saves back to summary', (
    tester,
  ) async {
    final (service, users) = await pump(tester);
    expect(find.byType(AlertDialog), findsNothing);
    await tester.tap(find.text('Display name'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'New name');
    await tester.pump();
    expect(service.profile, isNull, reason: 'nothing stored before Save');

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Name saved.'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.profile!.displayName, 'New name');
    expect(users.upserts.single.displayName, 'New name');
  });

  testWidgets('avatar picker uses simplified single sheet with quick actions', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byIcon(Icons.camera_alt_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Profile picture'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.text('Colors & initials'), findsOneWidget);
  });

  testWidgets('a failed save stays in dialog with an error', (
    tester,
  ) async {
    final (_, users) = await pump(tester);
    users.fail = true;
    await tester.tap(find.text('Display name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'New name');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets('Cancel closes name dialog without saving', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Display name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Unsaved name');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Me'), findsWidgets);
  });

  testWidgets('Manage chat media opens from Profile', (tester) async {
    final loader = ChatMediaLoader(
      mediaRepository: _UnusedMedia(),
      cryptoService: ChatCryptoService(),
    )..setAccount(me.uid);
    addTearDown(loader.dispose);
    final manager = ChatMediaManagerService(
      messageCache: const NoopMessageCacheRepository(),
      messageRepository: _UnusedMessages(),
      mediaLoader: loader,
    );

    await pump(tester, mediaLoader: loader, mediaManagerService: manager);
    final mediaTile = find.widgetWithText(ListTile, 'Manage chat media');
    await tester.ensureVisible(mediaTile);
    await tester.pumpAndSettle();
    await tester.tap(mediaTile);
    await tester.pumpAndSettle();

    expect(find.text('Manage Media'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
  });
}
