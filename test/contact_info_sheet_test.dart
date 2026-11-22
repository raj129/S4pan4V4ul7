import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_loader.dart';
import 'package:photo_vault/features/chat/application/media/chat_media_manager_service.dart';
import 'package:photo_vault/features/chat/application/services/profile_service.dart';
import 'package:photo_vault/features/chat/application/services/data_sms_service.dart';
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

class _Sms implements DataSmsService {
  final numbers = <String, String>{};
  bool failRead = false;

  @override
  Future<String?> phone(String threadId) async {
    if (failRead) throw StateError('storage unavailable');
    return numbers[threadId];
  }

  @override
  Future<void> setPhone(String threadId, String? number) async {
    if (number == null) {
      numbers.remove(threadId);
    } else {
      numbers[threadId] = number;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
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
    DataSmsService? dataSms,
    ValueChanged<String?>? onSmsNumberChanged,
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
                dataSms: dataSms,
                onSmsNumberChanged: onSmsNumberChanged,
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

  testWidgets('profile adds, updates and removes a conversation-bound number', (
    tester,
  ) async {
    final sms = _Sms()..numbers['other-chat'] = '+441234567890';
    final changes = <String?>[];
    await pumpHost(
      tester,
      dataSms: sms,
      threadId: 'this-chat',
      onSmsNumberChanged: changes.add,
    );
    await open(tester);
    expect(find.text('Data SMS number'), findsOneWidget);
    expect(find.text('Add recipient mobile number'), findsOneWidget);
    await tester.tap(find.text('Data SMS number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '+12025550123');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(sms.numbers['this-chat'], '+12025550123');
    expect(find.textContaining('+12025550123'), findsOneWidget);
    await tester.tap(find.text('Data SMS number'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '+919876543210');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('+919876543210'), findsOneWidget);
    await tester.tap(find.text('Data SMS number'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(sms.numbers['this-chat'], isNull);
    expect(sms.numbers['other-chat'], '+441234567890');
    expect(changes, ['+12025550123', '+919876543210', null]);
    expect(find.text('Add recipient mobile number'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile displays existing number and can retry a read error', (
    tester,
  ) async {
    final sms = _Sms()
      ..numbers['chat'] = '+12025550123'
      ..failRead = true;
    await pumpHost(tester, dataSms: sms, threadId: 'chat');
    await open(tester);
    expect(
      find.textContaining('Could not load Data SMS number'),
      findsOneWidget,
    );
    sms.failRead = false;
    await tester.tap(find.text('Data SMS number'));
    await tester.pumpAndSettle();
    expect(find.textContaining('+12025550123'), findsOneWidget);
  });

  testWidgets('profile without SMS service does not offer unsupported setup', (
    tester,
  ) async {
    await pumpHost(tester, threadId: 'chat');
    await open(tester);
    expect(find.text('Data SMS number'), findsNothing);
  });

  testWidgets('nickname edit mode saves, cancels and clears the alias', (
    tester,
  ) async {
    await pumpHost(tester);

    await open(tester);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Nickname visible only to you'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'B');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'B');
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Nickname visible only to you'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'C');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'C');

    await tester.tap(find.text('Nickname visible only to you'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'unsaved');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'C');

    await tester.tap(find.text('Nickname visible only to you'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use real name'));
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
    expect(card.elevation, 0);
    expect(find.byType(Card), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Nickname visible only to you'), findsOneWidget);

    // Profile picture can be tapped to view full avatar
    await tester.tap(find.byTooltip('View profile picture'));
    await tester.pumpAndSettle();
    expect(find.text('Close'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('a blank nickname removes it', (tester) async {
    await pumpHost(tester);
    await service.setAlias('a', 'B');

    await open(tester);
    await tester.tap(find.text('Nickname visible only to you'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), isNull);
  });

  testWidgets(
    'per-chat media opens from contact profile',
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
      await tester.tap(find.text('Media in this chat'));
      await tester.pumpAndSettle();

      expect(find.text('Media in this chat'), findsWidgets);
      expect(find.text('No media found'), findsOneWidget);
      expect(cache.loadedThreads, ['thread-a']);
    },
  );

  testWidgets('Cancel closes nickname dialog without saving', (
    tester,
  ) async {
    await pumpHost(tester);
    await open(tester);
    await tester.tap(find.text('Nickname visible only to you'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(service.aliasFor('a'), isNull);
  });
}
