import 'package:flutter/foundation.dart';

import '../../crypto/services/chat_crypto_service.dart';
import '../../domain/repositories/chat_search_index_repository.dart';
import '../../domain/search/chat_search_tokenizer.dart';

/// Plaintext of one message to index. A null [text] marks a message with
/// nothing searchable (media, deleted, undecryptable) so it is recorded as
/// indexed and never revisited.
typedef ChatIndexInput = ({String messageId, DateTime sentAt, String? text});

/// Writes decrypted message text into the keyed local search index and runs
/// queries against it.
class ChatSearchIndexer {
  ChatSearchIndexer({required this.index, required this.cryptoService});

  final ChatSearchIndexRepository index;
  final ChatCryptoService cryptoService;

  /// Batches larger than this are hashed on a background isolate so indexing
  /// years of history never janks the UI thread.
  static const _isolateThreshold = 64;

  Future<void> indexTexts(String threadId, List<ChatIndexInput> inputs) async {
    if (inputs.isEmpty) return;
    final key = await cryptoService.searchKey(threadId);
    final texts = [for (final i in inputs) i.text ?? ''];
    final tokens = texts.length > _isolateThreshold
        ? await compute(_hashAll, (key, texts))
        : _hashAll((key, texts));
    await index.index(threadId, [
      for (var i = 0; i < inputs.length; i++)
        ChatSearchEntry(
          messageId: inputs[i].messageId,
          sentAt: inputs[i].sentAt,
          tokens: tokens[i],
        ),
    ]);
  }

  Future<void> remove(List<String> messageIds) => index.remove(messageIds);

  /// Newest-first matches for [query] across the thread's whole local history.
  Future<List<ChatSearchHit>> search(String threadId, String query) async {
    if (ChatSearchTokenizer.queryTerms(query).isEmpty) return const [];
    final key = await cryptoService.searchKey(threadId);
    return index.search(
      threadId,
      ChatSearchTokenizer.hashedQueryTerms(key, query),
    );
  }
}

List<List<String>> _hashAll((Uint8List, List<String>) args) {
  final (key, texts) = args;
  return [
    for (final t in texts)
      t.isEmpty
          ? const <String>[]
          : ChatSearchTokenizer.hashedIndexTerms(key, t),
  ];
}
