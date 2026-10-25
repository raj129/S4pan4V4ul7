import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/storage/local_db/vault_database.dart';
import 'package:photo_vault/features/chat/data/repositories/drift_chat_draft_repository.dart';

void main() {
  late VaultDatabase database;
  late DriftChatDraftRepository drafts;

  setUp(() {
    database = VaultDatabase.forTesting(NativeDatabase.memory());
    drafts = DriftChatDraftRepository(database);
  });

  tearDown(() => database.close());

  test(
    'stores ciphertext independently for each thread and replaces it',
    () async {
      await drafts.save('thread-a', 'ciphertext-a');
      await drafts.save('thread-b', 'ciphertext-b');
      await drafts.save('thread-a', 'new-ciphertext-a');

      expect(await drafts.load('thread-a'), 'new-ciphertext-a');
      expect(await drafts.load('thread-b'), 'ciphertext-b');
      expect(await database.getChatDraft('thread-a'), isNotNull);
      expect(await drafts.load('missing-thread'), isNull);
    },
  );

  test('deletes one thread draft without affecting others', () async {
    await drafts.save('thread-a', 'ciphertext-a');
    await drafts.save('thread-b', 'ciphertext-b');

    await drafts.delete('thread-a');

    expect(await drafts.load('thread-a'), isNull);
    expect(await drafts.load('thread-b'), 'ciphertext-b');
  });

  test('clearing a thread also removes its local draft', () async {
    await drafts.save('thread-a', 'ciphertext-a');
    await drafts.save('thread-b', 'ciphertext-b');

    await database.deleteCachedThread('thread-a');

    expect(await drafts.load('thread-a'), isNull);
    expect(await drafts.load('thread-b'), 'ciphertext-b');
  });
}
