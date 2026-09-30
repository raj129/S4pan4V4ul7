import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/profile_service.dart';
import 'package:photo_vault/data/repositories_impl/firebase_avatar_storage.dart';
import 'package:photo_vault/domain/entities/chat_user.dart';
import 'package:photo_vault/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/domain/repositories/user_repository.dart';
import 'package:photo_vault/presentation/widgets/chat/contact_info_sheet.dart';

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

void main() {
  final user = ChatUser(
    uid: 'a',
    email: 'a@example.com',
    displayName: 'Person A',
    publicKey: '',
    createdAt: DateTime.utc(2024),
  );

  late ProfileService service;

  Future<void> pumpHost(WidgetTester tester) async {
    service = ProfileService(
      store: _Store(),
      userRepository: _Users(),
      avatarStorage: _Avatars(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showContactInfoSheet(
                context,
                profileService: service,
                user: user,
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

  testWidgets('save, edit, reset and cancel close cleanly', (tester) async {
    await pumpHost(tester);

    await open(tester);
    await tester.enterText(find.byType(TextField), 'B');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'B');
    expect(tester.takeException(), isNull);

    await open(tester);
    await tester.enterText(find.byType(TextField), 'C');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'C');

    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), 'C');

    await open(tester);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a blank nickname removes it', (tester) async {
    await pumpHost(tester);
    await service.setAlias('a', 'B');

    await open(tester);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(service.aliasFor('a'), isNull);
  });
}
