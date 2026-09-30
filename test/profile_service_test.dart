import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/profile_service.dart';
import 'package:photo_vault/data/repositories_impl/firebase_avatar_storage.dart';
import 'package:photo_vault/domain/entities/chat_user.dart';
import 'package:photo_vault/domain/entities/profile_avatar.dart';
import 'package:photo_vault/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/domain/repositories/user_repository.dart';

class _MemoryStore extends NoopMessageCacheRepository {
  _MemoryStore();
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

class _FakeUsers implements UserRepository {
  ChatUser? remote;
  final upserts = <ChatUser>[];

  @override
  Future<ChatUser?> getUserById(String uid) async => remote;

  @override
  Future<void> upsertProfile(ChatUser user, {bool includeProfile = true}) async {
    upserts.add(user);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAvatars implements AvatarStorage {
  @override
  Future<String> upload(String uid, dynamic bytes) async => 'https://x/y';

  @override
  Future<void> delete(String uid) async {}
}

ChatUser _user(String uid, String name) => ChatUser(
  uid: uid,
  email: '$uid@example.com',
  displayName: name,
  publicKey: '',
  createdAt: DateTime.utc(2024),
);

void main() {
  late _MemoryStore store;
  late _FakeUsers users;
  late ProfileService service;

  setUp(() {
    store = _MemoryStore();
    users = _FakeUsers();
    service = ProfileService(
      store: store,
      userRepository: users,
      avatarStorage: _FakeAvatars(),
    );
  });

  test('ProfileAvatar round-trips and rejects non-https photos', () {
    for (final a in const [
      ProfileAvatar.initials(),
      ProfileAvatar.preset(4),
      ProfileAvatar.emoji('😀'),
      ProfileAvatar.photo('https://x/y.jpg'),
    ]) {
      expect(ProfileAvatar.decode(a.encode()), a);
    }
    expect(
      ProfileAvatar.decode('photo:http://x'),
      const ProfileAvatar.initials(),
    );
    expect(ProfileAvatar.decode('junk'), const ProfileAvatar.initials());
  });

  test('alias replaces the display name only locally and can be reset', () async {
    final a = _user('a', 'Person A');
    expect(service.nameFor(a), 'Person A');
    await service.setAlias('a', '  B  ');
    expect(service.nameFor(a), 'B');
    await service.setAlias('a', '');
    expect(service.nameFor(a), 'Person A');
    expect(users.upserts, isEmpty);
  });

  test('ensureProfile adopts the server profile before the Google name', () async {
    users.remote = _user('me', 'Chosen').copyWith(
      avatar: const ProfileAvatar.emoji('🐱'),
    );
    final p = await service.ensureProfile(uid: 'me', fallbackName: 'Google');
    expect(p.displayName, 'Chosen');
    expect(p.avatar, const ProfileAvatar.emoji('🐱'));
  });

  test('updateProfile stores locally and publishes', () async {
    final me = _user('me', 'Google');
    await service.ensureProfile(uid: 'me', fallbackName: 'Google');
    await service.updateProfile(
      me: me,
      displayName: 'Nick',
      avatar: const ProfileAvatar.preset(2),
    );
    expect(users.upserts.single.displayName, 'Nick');

    final reloaded = ProfileService(
      store: store,
      userRepository: users,
      avatarStorage: _FakeAvatars(),
    );
    await reloaded.load();
    expect(reloaded.profile!.displayName, 'Nick');
  });

  test('backup export/import restores profile and aliases', () async {
    await service.ensureProfile(uid: 'me', fallbackName: 'Me');
    await service.setAlias('a', 'B');
    final data = await service.exportForBackup();

    final fresh = ProfileService(
      store: _MemoryStore(),
      userRepository: _FakeUsers(),
      avatarStorage: _FakeAvatars(),
    );
    await fresh.importFromBackup(data);
    expect(fresh.profile!.displayName, 'Me');
    expect(fresh.aliasFor('a'), 'B');
  });
}
