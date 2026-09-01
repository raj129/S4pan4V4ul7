import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/contact_discovery_service.dart';
import 'package:photo_vault/domain/entities/chat_user.dart';
import 'package:photo_vault/domain/repositories/user_repository.dart';

class _FakeContactSource implements ContactSource {
  _FakeContactSource({this.granted = true, this.contacts = const []});

  final bool granted;
  final List<DeviceContact> contacts;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Future<List<DeviceContact>> read() async => contacts;
}

class _FakeUserRepository implements UserRepository {
  _FakeUserRepository(this.registered);

  /// email (lower case) → user
  final Map<String, ChatUser> registered;

  /// Every chunk passed to [getUsersByEmails], so chunking can be asserted.
  final List<List<String>> queries = [];

  @override
  Future<List<ChatUser>> getUsersByEmails(List<String> emails) async {
    queries.add(List.of(emails));
    return [
      for (final email in emails)
        if (registered[email.toLowerCase()] != null) registered[email]!,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not needed');
}

ChatUser _user(String uid, String email) => ChatUser(
  uid: uid,
  email: email,
  displayName: uid,
  publicKey: 'pk_$uid',
  createdAt: DateTime.utc(2024),
);

void main() {
  group('ContactDiscoveryService', () {
    test('reports a denied permission distinctly from no matches', () async {
      final service = ContactDiscoveryService(
        userRepository: _FakeUserRepository({}),
        contacts: _FakeContactSource(granted: false),
      );

      final result = await service.discover(myUid: 'me');

      // The UI needs to tell "you said no" apart from "nobody you know is
      // here", because only the first is worth offering a retry for.
      expect(result.permissionGranted, isFalse);
      expect(result.matches, isEmpty);
    });

    test('an empty address book grants but matches nothing', () async {
      final service = ContactDiscoveryService(
        userRepository: _FakeUserRepository({}),
        contacts: _FakeContactSource(contacts: const []),
      );

      final result = await service.discover(myUid: 'me');

      expect(result.permissionGranted, isTrue);
      expect(result.matches, isEmpty);
    });

    test('matches registered contacts and prefers the address-book name',
        () async {
      final repo = _FakeUserRepository({
        'bob@example.com': _user('bob', 'bob@example.com'),
      });
      final service = ContactDiscoveryService(
        userRepository: repo,
        contacts: _FakeContactSource(
          contacts: const [
            DeviceContact(name: 'Bobby At Work', emails: ['Bob@Example.com']),
            DeviceContact(name: 'Nobody', emails: ['ghost@example.com']),
          ],
        ),
      );

      final result = await service.discover(myUid: 'me');

      expect(result.matches, hasLength(1));
      expect(result.matches.single.user.uid, 'bob');
      // The saved name is more recognisable than the Google account name.
      expect(result.matches.single.contactName, 'Bobby At Work');
      // Lookup is case-insensitive.
      expect(repo.queries.single, contains('bob@example.com'));
    });

    test('collapses duplicates and skips malformed addresses', () async {
      final repo = _FakeUserRepository({
        'bob@example.com': _user('bob', 'bob@example.com'),
      });
      final service = ContactDiscoveryService(
        userRepository: repo,
        contacts: _FakeContactSource(
          contacts: const [
            DeviceContact(name: 'First Entry', emails: ['bob@example.com']),
            DeviceContact(name: 'Second Entry', emails: ['BOB@example.com']),
            DeviceContact(name: 'Broken', emails: ['not-an-email', '  ']),
          ],
        ),
      );

      final result = await service.discover(myUid: 'me');

      expect(repo.queries.single, ['bob@example.com']);
      expect(result.scannedEmails, 1);
      expect(result.matches, hasLength(1));
      // First name seen wins, so the list does not flicker between scans.
      expect(result.matches.single.contactName, 'First Entry');
    });

    test('never offers a chat with yourself', () async {
      final repo = _FakeUserRepository({
        'me@example.com': _user('me', 'me@example.com'),
      });
      final service = ContactDiscoveryService(
        userRepository: repo,
        contacts: _FakeContactSource(
          contacts: const [
            DeviceContact(name: 'Me', emails: ['me@example.com']),
          ],
        ),
      );

      expect((await service.discover(myUid: 'me')).matches, isEmpty);
    });

    test('chunks lookups to stay within the whereIn limit', () async {
      final emails = [for (var i = 0; i < 65; i++) 'user$i@example.com'];
      final repo = _FakeUserRepository({});
      final service = ContactDiscoveryService(
        userRepository: repo,
        contacts: _FakeContactSource(
          contacts: [
            for (final email in emails)
              DeviceContact(name: email, emails: [email]),
          ],
        ),
      );

      await service.discover(myUid: 'me');

      // Firestore rejects a whereIn with more than 30 values, so an address
      // book of any size must be split.
      expect(repo.queries.map((q) => q.length).toList(), [30, 30, 5]);
      expect(repo.queries.expand((q) => q).toSet(), emails.toSet());
    });

    test('sorts matches by contact name', () async {
      final repo = _FakeUserRepository({
        'z@example.com': _user('z', 'z@example.com'),
        'a@example.com': _user('a', 'a@example.com'),
      });
      final service = ContactDiscoveryService(
        userRepository: repo,
        contacts: _FakeContactSource(
          contacts: const [
            DeviceContact(name: 'Zoe', emails: ['z@example.com']),
            DeviceContact(name: 'alice', emails: ['a@example.com']),
          ],
        ),
      );

      final result = await service.discover(myUid: 'me');

      expect(
        result.matches.map((m) => m.contactName).toList(),
        ['alice', 'Zoe'],
      );
    });
  });
}
