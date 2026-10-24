import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_vault/features/chat/application/services/profile_service.dart';
import 'package:photo_vault/features/chat/data/repositories/firebase_avatar_storage.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_user.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
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

void main() {
  final me = ChatUser(
    uid: 'me',
    email: 'me@example.com',
    displayName: 'Me',
    publicKey: '',
    createdAt: DateTime.utc(2024),
  );

  Future<(ProfileService, _Users)> pump(WidgetTester tester) async {
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
          builder: (_, _) => ProfileScreen(me: me, service: service),
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

  testWidgets('save is disabled until edited, then returns with a message', (
    tester,
  ) async {
    final (service, users) = await pump(tester);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'New name');
    await tester.pump();
    expect(service.profile, isNull, reason: 'nothing stored before Save');

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('chat list'), findsOneWidget);
    expect(find.text('Profile saved.'), findsOneWidget);
    expect(service.profile!.displayName, 'New name');
    expect(users.upserts.single.displayName, 'New name');
  });

  testWidgets('avatar picker uses Material 3 tabs and photo source cards', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Change picture'));
    await tester.pumpAndSettle();

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Emoji'), findsOneWidget);
    expect(find.text('Photo'), findsOneWidget);

    await tester.tap(find.text('Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Choose from gallery'), findsOneWidget);
    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.byType(Card), findsAtLeastNWidgets(1));
  });

  testWidgets('a failed save stays on the screen with an error', (
    tester,
  ) async {
    final (_, users) = await pump(tester);
    users.fail = true;
    await tester.enterText(find.byType(TextField), 'New name');
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.text('chat list'), findsNothing);
    expect(find.textContaining('Could not save'), findsOneWidget);
  });

  testWidgets('leaving with unsaved edits asks to discard', (tester) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'Changed');
    await tester.pump();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('chat list'), findsOneWidget);
  });
}
