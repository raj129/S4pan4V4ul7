import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_loader.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_manager_service.dart';
import 'package:photo_vault/features/chat/application/services/profile_service.dart';
import 'package:photo_vault/features/chat/data/repositories/firebase_avatar_storage.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_user.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/user_repository.dart';
import 'package:photo_vault/features/chat/presentation/widgets/contact_info_sheet.dart';
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

class _TrackedCache extends NoopMessageCacheRepository {
  final loadedThreads = <String>[];

  @override
  Future<List<ChatMessage>> loadAll(String threadId) async {
    loadedThreads.add(threadId);
    return const [];
  }
}

void main() {
  final user = ChatUser(
    uid: 'a',
    email: 'a@example.com',
    displayName: 'Person A',
    publicKey: '',
    createdAt: DateTime.utc(2024),
  );

  late ProfileService service;

  Future<void> pumpHost(
    WidgetTester tester, {
    ChatMediaLoader? mediaLoader,
    ChatMediaManagerService? mediaManagerService,
    String? threadId,
  }) async {
    service = ProfileService(
      store: _Store(),
      userRepository: _Users(),
      avatarStorage: _Avatars(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContactInfoSheet(
                context,
                profileService: service,
                user: user,
                mediaLoader: mediaLoader,
                mediaManagerService: mediaManagerService,
                threadId: threadId,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('nickname edit mode saves, cancels and clears the alias', (
    tester,
  ) async {
    await pumpHost(tester);

    await open(tester);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Edit nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'B');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'B');
    expect(find.byType(TextField), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Edit nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'C');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'C');

    await tester.tap(find.text('Edit nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'C');

    await tester.tap(find.text('Edit nickname'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use real name'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('contact profile uses Material 3 cards and view actions', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester);

    final card = tester.widget<Card>(find.byType(Card).first);
    expect(AppTheme.light.useMaterial3, isTrue);
    expect(card.shape, isNull);
    expect(find.byType(Card), findsAtLeastNWidgets(2));
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Edit nickname'), findsOneWidget);
  });

  testWidgets('a blank nickname removes it', (tester) async {
    await pumpHost(tester);
    await service.setAlias('a', 'B');

    await open(tester);
    await tester.tap(find.text('Edit nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), isNull);
  });

  testWidgets(
    'per-chat media opens over contact profile without saving draft',
    (tester) async {
      final loader = ChatMediaLoader(
        mediaRepository: _UnusedMedia(),
        cryptoService: ChatCryptoService(),
      )..setAccount(user.uid);
      addTearDown(loader.dispose);
      final cache = _TrackedCache();
      final manager = ChatMediaManagerService(
        messageCache: cache,
        messageRepository: _UnusedMessages(),
        mediaLoader: loader,
      );

      await pumpHost(
        tester,
        mediaLoader: loader,
        mediaManagerService: manager,
        threadId: 'thread-a',
      );
      await open(tester);
      await tester.tap(find.text('Edit nickname'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Draft nickname');
      await tester.tap(find.text('Media in this chat'));
      await tester.pumpAndSettle();

      expect(find.text('Media in this chat'), findsWidgets);
      expect(find.text('No media found'), findsOneWidget);
      expect(cache.loadedThreads, ['thread-a']);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Draft nickname',
      );
      expect(service.aliasFor(user.uid), isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.aliasFor(user.uid), isNull);
    },
  );

  testWidgets('system Back confirms before discarding nickname edits', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester);
    await tester.tap(find.text('Edit nickname'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard nickname changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
    expect(service.aliasFor(user.uid), isNull);
  });
}
