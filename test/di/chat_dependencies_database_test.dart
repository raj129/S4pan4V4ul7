import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/core/domain/repositories/auth_repository.dart';
import 'package:photo_vault/core/session/vault_session.dart';
import 'package:photo_vault/core/storage/local_db/vault_database.dart';
import 'package:photo_vault/features/chat/data/repositories/drift_chat_draft_repository.dart';
import 'package:photo_vault/features/chat/data/repositories/drift_chat_search_index_repository.dart';
import 'package:photo_vault/features/chat/data/repositories/drift_message_cache_repository.dart';
import 'package:photo_vault/features/chat/data/repositories/drift_outbox_repository.dart';
import 'package:photo_vault/features/chat/di/chat_dependencies.dart';

class _Auth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

class _Database implements VaultDatabase {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  test('dependencies created before database startup resolve it lazily', () {
    VaultDatabase? openedDatabase;
    final chat = ChatDependencies(
      authRepository: _Auth(),
      vaultSession: VaultSession(),
      databaseProvider: () => openedDatabase,
    );

    openedDatabase = _Database();

    expect(chat.messageCache, isA<DriftMessageCacheRepository>());
    expect(chat.searchIndex, isA<DriftChatSearchIndexRepository>());
    expect(chat.outbox, isA<DriftOutboxRepository>());
    expect(chat.draftRepository, isA<DriftChatDraftRepository>());
  });

  test(
    'explicit database override takes precedence over a deferred provider',
    () {
      final override = _Database();
      final laterDatabase = _Database();
      final chat = ChatDependencies(
        authRepository: _Auth(),
        vaultSession: VaultSession(),
        database: override,
        databaseProvider: () => laterDatabase,
      );

      expect(chat.messageCache, isA<DriftMessageCacheRepository>());
      expect(chat.searchIndex, isA<DriftChatSearchIndexRepository>());
      expect(chat.outbox, isA<DriftOutboxRepository>());
      expect(chat.draftRepository, isA<DriftChatDraftRepository>());
    },
  );
}
