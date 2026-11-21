import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_thread.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_user.dart';
import 'package:photo_vault/features/chat/domain/entities/user_presence.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/presence_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/thread_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/user_repository.dart';
import 'package:photo_vault/features/chat/presentation/state/thread_list_cubit.dart';

class _FakeThreadRepo implements ThreadRepository {
  final _ctrl = StreamController<List<ChatThread>>.broadcast();

  void emitThreads(List<ChatThread> threads) => _ctrl.add(threads);

  @override
  Stream<List<ChatThread>> watchThreadsForUser(String uid) => _ctrl.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeUserRepo implements UserRepository {
  _FakeUserRepo(this.users);

  final Map<String, ChatUser> users;
  final List<bool> preferCacheCalls = [];

  @override
  Future<ChatUser?> getUserById(String uid, {bool preferCache = false}) async {
    preferCacheCalls.add(preferCache);
    return users[uid];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessageRepo implements MessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaRepo implements MediaRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePresenceRepo implements PresenceRepository {
  @override
  Stream<Map<String, UserPresence>> watchMany(List<String> uids) =>
      Stream.value(const {});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMessageCache implements MessageCacheRepository {
  @override
  Future<DateTime?> getClearedBefore(String threadId) async => null;

  @override
  Future<DateTime?> getHistoryHorizon() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'ThreadListCubit requests cache-first user lookups and emits loaded threads',
    () async {
      final threadRepo = _FakeThreadRepo();
      final userRepo = _FakeUserRepo({
        'u2': ChatUser(
          uid: 'u2',
          email: 'u2@example.com',
          displayName: 'User Two',
          publicKey: '',
          createdAt: DateTime.utc(2026),
        ),
        'u3': ChatUser(
          uid: 'u3',
          email: 'u3@example.com',
          displayName: 'User Three',
          publicKey: '',
          createdAt: DateTime.utc(2026),
        ),
      });

      final cubit = ThreadListCubit(
        threadRepository: threadRepo,
        userRepository: userRepo,
        messageRepository: _FakeMessageRepo(),
        mediaRepository: _FakeMediaRepo(),
        presenceRepository: _FakePresenceRepo(),
        messageCache: _FakeMessageCache(),
        myUid: 'u1',
      );
      addTearDown(cubit.close);

      cubit.startWatching();
      threadRepo.emitThreads([
        ChatThread(
          threadId: 'u1_u2',
          participantIds: const ['u1', 'u2'],
          lastMessage: 'hi',
          lastMessageAt: DateTime.utc(2026, 1, 2),
          unreadCounts: const {'u1': 0, 'u2': 0},
          createdAt: DateTime.utc(2026, 1, 1),
        ),
        ChatThread(
          threadId: 'u1_u3',
          participantIds: const ['u1', 'u3'],
          lastMessage: 'hey',
          lastMessageAt: DateTime.utc(2026, 1, 3),
          unreadCounts: const {'u1': 1, 'u3': 0},
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      ]);

      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(userRepo.preferCacheCalls, [true, true]);
      expect(cubit.state, isA<ThreadListLoaded>());
      final loaded = cubit.state as ThreadListLoaded;
      expect(loaded.items, hasLength(2));
    },
  );
}
