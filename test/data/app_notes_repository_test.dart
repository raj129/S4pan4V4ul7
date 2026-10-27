import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/crypto/chat_crypto_service.dart';
import 'package:photo_vault/features/chat/data/repositories/app_notes_repository.dart';
import 'package:photo_vault/features/chat/domain/entities/app_note.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_string_kv.dart';

class _MemoryKv implements StorageStringKv {
  final values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _UnusedCrypto implements ChatCryptoService {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

AppNote _note(String id, DateTime edited, {bool pinned = false}) => AppNote(
  id: id,
  creatorId: 'me',
  type: NoteType.textNote,
  title: id,
  createdAt: DateTime.utc(2024),
  updatedAt: edited,
  isPinned: pinned,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'private notes reload and sort pinned first then by edit time',
    () async {
      final kv = _MemoryKv();
      final repository = AppNotesRepository(
        cryptoService: _UnusedCrypto(),
        secureKv: kv,
      );
      await repository.savePrivateNote(
        _note('old', DateTime.utc(2024, 1, 1), pinned: true),
      );
      final first = await repository.watchPrivateNotes().first;
      expect(first.map((note) => note.id), ['old']);

      await repository.savePrivateNote(_note('new', DateTime.utc(2024, 1, 3)));
      final reopened = await repository.watchPrivateNotes().first;
      expect(reopened.map((note) => note.id), ['old', 'new']);

      final newRepository = AppNotesRepository(
        cryptoService: _UnusedCrypto(),
        secureKv: kv,
      );
      expect(
        (await newRepository.watchPrivateNotes().first).map((note) => note.id),
        ['old', 'new'],
      );
    },
  );

  test(
    'a corrupt private index reports an error instead of an empty list',
    () async {
      final kv = _MemoryKv();
      kv.values['vault_private_notes_index'] = 'invalid json';
      final repository = AppNotesRepository(
        cryptoService: _UnusedCrypto(),
        secureKv: kv,
      );

      await expectLater(
        repository.watchPrivateNotes().first,
        throwsFormatException,
      );
    },
  );
}
