import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/services/chat_notification_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_thread.dart';
import 'package:photo_vault/features/chat/domain/repositories/thread_repository.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';

class _ThreadRepository implements ThreadRepository {
  // ignore: close_sinks - test fake lives for the whole test.
  final updates = StreamController<List<ChatThread>>.broadcast(sync: true);

  @override
  Stream<List<ChatThread>> watchThreadsForUser(String uid) => updates.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ChatThread _thread(String id, int unread) => ChatThread(
  threadId: id,
  participantIds: const ['alice', 'bob'],
  lastMessage: '',
  lastMessageAt: DateTime.utc(2026),
  unreadCounts: {'alice': unread},
  createdAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'coalesces rapid unread changes per thread without changing the text',
    () async {
      final repository = _ThreadRepository();
      var now = DateTime.utc(2026);
      final notifications = <({String threadId, String title, String body})>[];
      final service = ChatNotificationService(
        threadRepository: repository,
        isAppForeground: () => false,
        clock: () => now,
        presentNotification:
            ({required threadId, required title, required body}) async {
              notifications.add((threadId: threadId, title: title, body: body));
            },
      );

      await service.start('alice');
      repository.updates.add([_thread('alice_bob', 0)]);
      repository.updates.add([_thread('alice_bob', 1)]);
      repository.updates.add([_thread('alice_bob', 2)]);
      await Future<void>.delayed(Duration.zero);

      expect(notifications, hasLength(1));
      expect(notifications.single.threadId, 'alice_bob');
      expect(notifications.single.title, isEmpty);
      expect(notifications.single.body, isEmpty);

      now = now.add(const Duration(seconds: 31));
      repository.updates.add([_thread('alice_bob', 3)]);
      await Future<void>.delayed(Duration.zero);
      expect(notifications, hasLength(2));
      expect(notifications.last.title, isEmpty);
      expect(notifications.last.body, isEmpty);

      await service.dispose();
      await repository.updates.close();
    },
  );

  test('uses the saved incoming-chat alert text', () async {
    final repository = _ThreadRepository();
    final settings = InMemorySettingsRepository();
    await settings.setIncomingChatAlertTitle('Private');
    await settings.setIncomingChatAlertText('New message received');
    final notifications = <({String title, String body})>[];
    final service = ChatNotificationService(
      threadRepository: repository,
      settingsRepository: settings,
      isAppForeground: () => false,
      presentNotification:
          ({required threadId, required title, required body}) async {
            notifications.add((title: title, body: body));
          },
    );

    await service.start('alice');
    repository.updates.add([_thread('alice_bob', 0)]);
    repository.updates.add([_thread('alice_bob', 1)]);
    await Future<void>.delayed(Duration.zero);

    expect(notifications, [(title: 'Private', body: 'New message received')]);

    await service.dispose();
    await repository.updates.close();
  });

  test('keeps a blank body for received and test notifications', () async {
    final repository = _ThreadRepository();
    final settings = InMemorySettingsRepository();
    await settings.setIncomingChatAlertText('');
    final notifications = <({String threadId, String title, String body})>[];
    final service = ChatNotificationService(
      threadRepository: repository,
      settingsRepository: settings,
      isAppForeground: () => false,
      presentNotification:
          ({required threadId, required title, required body}) async {
            notifications.add((threadId: threadId, title: title, body: body));
          },
    );

    await service.start('alice');
    repository.updates.add([_thread('alice_bob', 0)]);
    repository.updates.add([_thread('alice_bob', 1)]);
    await Future<void>.delayed(Duration.zero);
    await service.showTestNotification();

    expect(notifications, [
      (threadId: 'alice_bob', title: '', body: ''),
      (threadId: 'test-notification', title: '', body: ''),
    ]);

    await service.dispose();
    await repository.updates.close();
  });

  test(
    'keeps notifications independent across different conversations',
    () async {
      final repository = _ThreadRepository();
      final notifications = <String>[];
      final service = ChatNotificationService(
        threadRepository: repository,
        isAppForeground: () => false,
        presentNotification:
            ({required threadId, required title, required body}) async {
              notifications.add(threadId);
            },
      );

      await service.start('alice');
      repository.updates.add([
        _thread('alice_bob', 0),
        _thread('alice_cara', 0),
      ]);
      repository.updates.add([
        _thread('alice_bob', 1),
        _thread('alice_cara', 1),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(notifications, ['alice_bob', 'alice_cara']);

      await service.dispose();
      await repository.updates.close();
    },
  );

  test('emits an in-app alert outside the visible chat branch', () async {
    final repository = _ThreadRepository();
    final service = ChatNotificationService(
      threadRepository: repository,
      isAppForeground: () => true,
      presentNotification:
          ({required threadId, required title, required body}) async {},
    );

    await service.start('alice');
    repository.updates.add([_thread('alice_bob', 0)]);
    await service.setActiveThread('alice_bob');
    repository.updates.add([_thread('alice_bob', 1)]);
    await Future<void>.delayed(Duration.zero);
    expect(service.foregroundNotification.value, isNull);

    service.setChatSectionVisible(false);
    repository.updates.add([_thread('alice_bob', 2)]);
    await Future<void>.delayed(Duration.zero);

    expect(service.foregroundNotification.value, isNotNull);
    expect(service.foregroundNotification.value!.threadId, 'alice_bob');
    expect(service.foregroundNotification.value!.title, isEmpty);
    expect(service.isActiveThread('alice_bob'), isFalse);

    service.setChatSectionVisible(true);
    expect(service.isActiveThread('alice_bob'), isTrue);

    await service.dispose();
    await repository.updates.close();
  });
}
