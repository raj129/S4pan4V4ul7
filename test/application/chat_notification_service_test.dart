import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/services/chat_notification_service.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_thread.dart';
import 'package:photo_vault/features/chat/domain/repositories/thread_repository.dart';

class _ThreadRepository implements ThreadRepository {
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
  test(
    'coalesces rapid unread changes per thread without changing the text',
    () async {
      final repository = _ThreadRepository();
      var now = DateTime.utc(2026);
      final notifications = <({String threadId, String body})>[];
      final service = ChatNotificationService(
        threadRepository: repository,
        clock: () => now,
        presentNotification:
            ({required threadId, required title, required body}) async {
              notifications.add((threadId: threadId, body: body));
            },
      );

      await service.start('alice');
      repository.updates.add([_thread('alice_bob', 0)]);
      repository.updates.add([_thread('alice_bob', 1)]);
      repository.updates.add([_thread('alice_bob', 2)]);

      expect(notifications, hasLength(1));
      expect(notifications.single.threadId, 'alice_bob');
      expect(notifications.single.body, 'You have a new alert');

      now = now.add(const Duration(seconds: 31));
      repository.updates.add([_thread('alice_bob', 3)]);
      expect(notifications, hasLength(2));
      expect(notifications.last.body, 'You have a new alert');

      await service.dispose();
      await repository.updates.close();
    },
  );

  test(
    'keeps notifications independent across different conversations',
    () async {
      final repository = _ThreadRepository();
      final notifications = <String>[];
      final service = ChatNotificationService(
        threadRepository: repository,
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
}
