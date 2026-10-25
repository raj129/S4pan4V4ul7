import 'package:drift/drift.dart' show Value;

import '../../../../core/storage/local_db/vault_database.dart';
import '../../domain/repositories/chat_draft_repository.dart';

class DriftChatDraftRepository implements ChatDraftRepository {
  const DriftChatDraftRepository(this._database);

  final VaultDatabase _database;

  @override
  Future<String?> load(String threadId) async =>
      (await _database.getChatDraft(threadId))?.encryptedText;

  @override
  Future<void> save(String threadId, String encryptedText) =>
      _database.saveChatDraft(
        ChatDraftsCompanion(
          threadId: Value(threadId),
          encryptedText: Value(encryptedText),
          updatedAtMs: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
        ),
      );

  @override
  Future<void> delete(String threadId) => _database.deleteChatDraft(threadId);
}
