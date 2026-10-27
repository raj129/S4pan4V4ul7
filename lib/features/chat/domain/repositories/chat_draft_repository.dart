/// Local storage for encrypted chat composer drafts.
abstract interface class ChatDraftRepository {
  Future<String?> load(String threadId);

  Future<void> save(String threadId, String encryptedText);

  Future<void> delete(String threadId);
}

/// Used when chat persistence is unavailable, such as in isolated tests.
class NoopChatDraftRepository implements ChatDraftRepository {
  const NoopChatDraftRepository();

  @override
  Future<String?> load(String threadId) async => null;

  @override
  Future<void> save(String threadId, String encryptedText) async {}

  @override
  Future<void> delete(String threadId) async {}
}
