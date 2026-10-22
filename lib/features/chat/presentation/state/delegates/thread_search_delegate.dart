import 'dart:async';

import 'package:photo_vault/features/chat/application/services/chat_search_indexer.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_cache_repository.dart';
import 'package:photo_vault/features/chat/domain/repositories/message_repository.dart';
import '../active_thread_cubit.dart';

/// Handles message search indexing, query debouncing, match stepping,
/// and local cache catch-up and index backfilling for an active thread.
class ThreadSearchDelegate {
  ThreadSearchDelegate({
    required ChatSearchIndexer indexer,
    required MessageCacheRepository messageCache,
    required MessageRepository messageRepository,
    required String myUid,
    required String? Function() currentThreadId,
    required DateTime? Function() clearedBefore,
    required DateTime? Function() horizon,
    required ActiveThreadState Function() getState,
    required void Function(ActiveThreadState state) emit,
    required Future<bool> Function(String messageId) jumpToMessage,
    required Future<List<ChatMessage>> Function(
      List<ChatMessage> msgs,
      String threadId,
    )
    decryptAll,
    required bool Function() isClosed,
    required int Function() openGeneration,
  }) : _indexer = indexer,
       _messageCache = messageCache,
       _messageRepository = messageRepository,
       _myUid = myUid,
       _currentThreadId = currentThreadId,
       _clearedBefore = clearedBefore,
       _horizon = horizon,
       _getState = getState,
       _emit = emit,
       _jumpToMessage = jumpToMessage,
       _decryptAll = decryptAll,
       _isClosed = isClosed,
       _openGeneration = openGeneration;

  final ChatSearchIndexer _indexer;
  final MessageCacheRepository _messageCache;
  final MessageRepository _messageRepository;
  final String _myUid;
  final String? Function() _currentThreadId;
  final DateTime? Function() _clearedBefore;
  final DateTime? Function() _horizon;
  final ActiveThreadState Function() _getState;
  final void Function(ActiveThreadState state) _emit;
  final Future<bool> Function(String messageId) _jumpToMessage;
  final Future<List<ChatMessage>> Function(
    List<ChatMessage> msgs,
    String threadId,
  )
  _decryptAll;
  final bool Function() _isClosed;
  final int Function() _openGeneration;

  ChatSearchIndexer get indexer => _indexer;

  static const _searchDebounceDuration = Duration(milliseconds: 250);

  /// Placeholder bodies that must never count as a match.
  static const unsearchableTexts = {
    '🚫 Message deleted',
    '🔒 Encrypted message',
  };

  Timer? _searchDebounce;

  /// Re-runs the active query after new messages are indexed.
  Timer? _searchRefresh;

  /// Bumped per query so a slow lookup cannot apply results for stale input.
  int _searchGeneration = 0;

  /// What is indexed per message (hash of ciphertext + searchability), so
  /// repeated live snapshots do not re-hash unchanged messages.
  final Map<String, int> _indexedSig = {};

  static const _catchUpPage = 100;
  static const _backfillPage = 200;

  void resetForThread() {
    _indexedSig.clear();
    _searchDebounce?.cancel();
    _searchRefresh?.cancel();
    _searchGeneration++;
  }

  /// Search the thread's whole local history for [query] and highlight the
  /// matches in place, without hiding any messages. Jumps to the newest
  /// match immediately, stepping to older ones with [nextMatch].
  void setSearchQuery(String query) {
    final current = _getState();
    if (current is! ActiveThreadLoaded) return;
    if (current.searchQuery == query) return;
    _searchDebounce?.cancel();
    _searchRefresh?.cancel();
    final generation = ++_searchGeneration;
    final trimmed = query.trim();
    _emit(
      current.copyWith(
        searchQuery: query,
        searchMatchIds: const [],
        clearCurrentMatch: true,
        searchInProgress: trimmed.isNotEmpty,
      ),
    );
    if (trimmed.isEmpty) return;
    _searchDebounce = Timer(
      _searchDebounceDuration,
      () => runSearch(trimmed, generation, jump: true),
    );
  }

  void clearSearch() => setSearchQuery('');

  /// Move to the next *older* match.
  Future<void> nextMatch() => stepMatch(1);

  /// Move to the next *newer* match.
  Future<void> previousMatch() => stepMatch(-1);

  Future<void> stepMatch(int delta) async {
    final current = _getState();
    if (current is! ActiveThreadLoaded) return;
    final ids = current.searchMatchIds;
    if (ids.isEmpty) return;
    final index = (current.currentMatchIndex + delta).clamp(0, ids.length - 1);
    if (ids[index] == current.currentMatchId) return;
    _emit(current.copyWith(currentMatchId: ids[index]));
    await _jumpToMessage(ids[index]);
  }

  Future<void> runSearch(
    String query,
    int generation, {
    required bool jump,
  }) async {
    final threadId = _currentThreadId();
    if (threadId == null) return;
    List<String> ids;
    try {
      final hits = await _indexer.search(threadId, query);
      final cutoff = _clearedBefore();
      ids = [
        for (final h in hits)
          if (cutoff == null || h.sentAt.isAfter(cutoff)) h.messageId,
      ];
    } catch (_) {
      ids = const [];
    }
    if (generation != _searchGeneration || threadId != _currentThreadId()) {
      return;
    }
    final current = _getState();
    if (current is! ActiveThreadLoaded) return;
    final keep = current.currentMatchId;
    final String? currentId = keep != null && ids.contains(keep)
        ? keep
        : (ids.isEmpty ? null : ids.first);
    _emit(
      current.copyWith(
        searchMatchIds: ids,
        currentMatchId: currentId,
        clearCurrentMatch: currentId == null,
        searchInProgress: false,
      ),
    );
    if (jump && currentId != null) await _jumpToMessage(currentId);
  }

  /// Refresh the result list (without moving) once more history is indexed.
  void scheduleSearchRefresh() {
    final current = _getState();
    if (current is! ActiveThreadLoaded || !current.isSearching) return;
    _searchRefresh?.cancel();
    final generation = _searchGeneration;
    final query = current.searchQuery.trim();
    _searchRefresh = Timer(const Duration(milliseconds: 400), () {
      final latest = _getState();
      if (generation != _searchGeneration ||
          latest is! ActiveThreadLoaded ||
          latest.searchInProgress) {
        return;
      }
      unawaited(
        runSearch(query, generation, jump: latest.currentMatchId == null),
      );
    });
  }

  /// The text a message contributes to search, or null if it has none.
  String? searchableText(ChatMessage m) {
    if (m.isMedia || m.deletedForEveryone || m.isDeletedFor(_myUid)) {
      return null;
    }
    final text = m.localDecryptedText;
    if (text == null || text.isEmpty || unsearchableTexts.contains(text)) {
      return null;
    }
    return text;
  }

  /// Index decrypted messages that changed since they were last indexed.
  void indexMessages(String threadId, Iterable<ChatMessage> msgs) {
    final inputs = <ChatIndexInput>[];
    for (final m in msgs) {
      final text = searchableText(m);
      final sig = Object.hash(m.encryptedText, text == null);
      if (_indexedSig[m.messageId] == sig) continue;
      _indexedSig[m.messageId] = sig;
      inputs.add((messageId: m.messageId, sentAt: m.sentAt, text: text));
    }
    if (inputs.isEmpty) return;
    unawaited(
      _indexer
          .indexTexts(threadId, inputs)
          .then((_) {
            if (threadId == _currentThreadId()) scheduleSearchRefresh();
          })
          .catchError((Object _) {
            for (final i in inputs) {
              _indexedSig.remove(i.messageId);
            }
          }),
    );
  }

  /// Catch the cache up with the server, then index any cached history that
  /// is not yet searchable (e.g. restored from a backup, or cached before the
  /// index existed).
  Future<void> syncLocalHistory(String threadId, int generation) async {
    bool stale() => generation != _openGeneration() || _isClosed();
    await catchUpCache(threadId, stale);
    if (stale()) return;
    await backfillIndex(threadId, stale);
  }

  /// Save every server message newer than the newest cached one, so local
  /// search covers the whole conversation and not only what was scrolled.
  Future<void> catchUpCache(String threadId, bool Function() stale) async {
    DateTime? cursor;
    try {
      cursor = (await _messageCache.timeBounds(threadId))?.$2;
    } catch (_) {
      return;
    }
    // A cold cache has no gap to fill; live snapshots seed it.
    if (cursor == null) return;
    final horizonDate = _horizon();
    if (horizonDate != null && horizonDate.isAfter(cursor)) {
      cursor = horizonDate;
    }
    final cutoff = _clearedBefore();
    if (cutoff != null && cutoff.isAfter(cursor)) cursor = cutoff;

    while (!stale()) {
      final List<ChatMessage> page;
      try {
        page = await _messageRepository.loadAfter(
          threadId: threadId,
          after: cursor!,
          limit: _catchUpPage,
        );
      } catch (_) {
        return; // Offline: the next open retries.
      }
      if (page.isEmpty || stale()) return;
      try {
        await _messageCache.save(page);
        indexMessages(threadId, await _decryptAll(page, threadId));
      } catch (_) {
        return;
      }
      final newest = page
          .map((m) => m.sentAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      if (page.length < _catchUpPage || !newest.isAfter(cursor)) return;
      cursor = newest;
    }
  }

  Future<void> backfillIndex(String threadId, bool Function() stale) async {
    int total;
    try {
      total = await _indexer.index.countUnindexed(threadId);
    } catch (_) {
      return;
    }
    if (total == 0) return;
    var done = 0;
    var previousFirst = '';
    try {
      while (!stale()) {
        final batch = await _indexer.index.unindexed(
          threadId,
          limit: _backfillPage,
        );
        // Guard against a row that can never be indexed looping forever.
        if (batch.isEmpty || batch.first.messageId == previousFirst) break;
        previousFirst = batch.first.messageId;
        final decrypted = await _decryptAll(batch, threadId);
        await _indexer.indexTexts(threadId, [
          for (final m in decrypted)
            (
              messageId: m.messageId,
              sentAt: m.sentAt,
              text: searchableText(m),
            ),
        ]);
        for (final m in decrypted) {
          _indexedSig[m.messageId] = Object.hash(
            m.encryptedText,
            searchableText(m) == null,
          );
        }
        done += batch.length;
        final current = _getState();
        if (stale() || current is! ActiveThreadLoaded) break;
        _emit(current.copyWith(indexingProgress: (done / total).clamp(0, 1)));
        scheduleSearchRefresh();
        if (batch.length < _backfillPage) break;
      }
    } catch (_) {
      // Unindexed rows are picked up again on the next open.
    }
    final current = _getState();
    if (!stale() && current is ActiveThreadLoaded) {
      _emit(current.copyWith(clearIndexingProgress: true));
      scheduleSearchRefresh();
    }
  }

  Future<void> remove(List<String> messageIds) async {
    try {
      await _indexer.remove(messageIds);
    } catch (_) {}
    for (final id in messageIds) {
      _indexedSig.remove(id);
    }
  }

  void dispose() {
    _searchDebounce?.cancel();
    _searchRefresh?.cancel();
  }
}
