import 'app_note.dart';

/// Performs a 3-way merge of [local] and [remote] against an optional [base]
/// snapshot so concurrent edits on different fields, checklist items, or lines
/// are preserved without silently overwriting either collaborator's work.
AppNote mergeAppNotes({
  required AppNote? base,
  required AppNote remote,
  required AppNote local,
}) {
  if (base == null) {
    return _twoWayMerge(remote: remote, local: local);
  }

  final preferLocal = !local.updatedAt.isBefore(remote.updatedAt);

  final mergedTitle = _mergeScalar(
    base: base.title,
    remote: remote.title,
    local: local.title,
    preferLocal: preferLocal,
  );
  final mergedType = _mergeScalar(
    base: base.type,
    remote: remote.type,
    local: local.type,
    preferLocal: preferLocal,
  );
  final mergedPinned = _mergeScalar(
    base: base.isPinned,
    remote: remote.isPinned,
    local: local.isPinned,
    preferLocal: preferLocal,
  );
  final mergedColor = _mergeScalar(
    base: base.colorIndex,
    remote: remote.colorIndex,
    local: local.colorIndex,
    preferLocal: preferLocal,
  );
  final mergedContent = _mergeText3Way(
    base: base.content,
    remote: remote.content,
    local: local.content,
  );
  final mergedItems = _mergeChecklistItems3Way(
    base: base.items,
    remote: remote.items,
    local: local.items,
    preferLocal: preferLocal,
  );

  final mergedUpdatedAt = local.updatedAt.isAfter(remote.updatedAt)
      ? local.updatedAt
      : remote.updatedAt;

  return remote.copyWith(
    type: mergedType,
    title: mergedTitle,
    content: mergedContent,
    items: mergedItems,
    updatedAt: mergedUpdatedAt,
    lastEditedBy: local.lastEditedBy ?? remote.lastEditedBy,
    isPinned: mergedPinned,
    colorIndex: mergedColor,
  );
}

AppNote _twoWayMerge({required AppNote remote, required AppNote local}) {
  final preferLocal = !local.updatedAt.isBefore(remote.updatedAt);
  final mergedTitle = local.title == remote.title
      ? local.title
      : (local.title.isEmpty
            ? remote.title
            : (remote.title.isEmpty
                  ? local.title
                  : (preferLocal ? local.title : remote.title)));

  final mergedContent = _mergeText3Way(
    base: '',
    remote: remote.content,
    local: local.content,
  );

  final mergedItems = _mergeChecklistItems3Way(
    base: const [],
    remote: remote.items,
    local: local.items,
    preferLocal: preferLocal,
  );

  return remote.copyWith(
    type: preferLocal ? local.type : remote.type,
    title: mergedTitle,
    content: mergedContent,
    items: mergedItems,
    updatedAt: local.updatedAt.isAfter(remote.updatedAt)
        ? local.updatedAt
        : remote.updatedAt,
    lastEditedBy: local.lastEditedBy ?? remote.lastEditedBy,
    isPinned: local.isPinned || remote.isPinned,
    colorIndex: preferLocal ? local.colorIndex : remote.colorIndex,
  );
}

T _mergeScalar<T>({
  required T base,
  required T remote,
  required T local,
  required bool preferLocal,
}) {
  if (local == remote) return local;
  if (local == base) return remote;
  if (remote == base) return local;
  return preferLocal ? local : remote;
}

List<ChecklistItem> _mergeChecklistItems3Way({
  required List<ChecklistItem> base,
  required List<ChecklistItem> remote,
  required List<ChecklistItem> local,
  required bool preferLocal,
}) {
  final baseById = {for (final item in base) item.id: item};
  final remoteById = {for (final item in remote) item.id: item};
  final localById = {for (final item in local) item.id: item};

  final baseOrder = base.map((i) => i.id).toList();
  final remoteOrder = remote.map((i) => i.id).toList();
  final localOrder = local.map((i) => i.id).toList();

  final remoteReordered = !_listEquals(
    remoteOrder.where(baseById.containsKey).toList(),
    baseOrder.where(remoteById.containsKey).toList(),
  );
  final localReordered = !_listEquals(
    localOrder.where(baseById.containsKey).toList(),
    baseOrder.where(localById.containsKey).toList(),
  );

  final primary = (localReordered && !remoteReordered) ? local : remote;
  final secondary = identical(primary, local) ? remote : local;

  final result = <ChecklistItem>[];
  final seen = <String>{};

  void addMerged(String id) {
    if (!seen.add(id)) return;
    final b = baseById[id];
    final r = remoteById[id];
    final l = localById[id];

    if (r != null && l != null) {
      if (b == null) {
        result.add(preferLocal ? l : r);
      } else {
        final mergedText = _mergeScalar(
          base: b.text,
          remote: r.text,
          local: l.text,
          preferLocal: preferLocal,
        );
        final mergedDone = _mergeScalar(
          base: b.isDone,
          remote: r.isDone,
          local: l.isDone,
          preferLocal: preferLocal,
        );
        final mergedCompletedAt = mergedDone
            ? _mergeScalar(
                base: b.completedAt,
                remote: r.completedAt,
                local: l.completedAt,
                preferLocal: preferLocal,
              )
            : null;
        final mergedCompletedBy = mergedDone
            ? _mergeScalar(
                base: b.completedBy,
                remote: r.completedBy,
                local: l.completedBy,
                preferLocal: preferLocal,
              )
            : null;
        result.add(
          ChecklistItem(
            id: id,
            text: mergedText,
            isDone: mergedDone,
            completedAt: mergedCompletedAt,
            completedBy: mergedCompletedBy,
          ),
        );
      }
      return;
    }

    if (r != null && l == null) {
      // Deleted locally or added remotely.
      // Preserve if newly added remotely, or if remote modified it since base.
      if (b == null || r != b) {
        result.add(r);
      }
      return;
    }

    if (l != null && r == null) {
      // Added locally or deleted remotely.
      // Preserve if newly added locally, or if local modified it since base.
      if (b == null || l != b) {
        result.add(l);
      }
    }
  }

  for (final item in primary) {
    addMerged(item.id);
  }
  for (final item in secondary) {
    addMerged(item.id);
  }
  return result;
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Line-based 3-way merge for plain text note content.
/// Non-overlapping edits on different lines are combined cleanly.
/// If both sides edit the same line range differently, both versions are
/// preserved so neither collaborator's text is silently lost.
String _mergeText3Way({
  required String base,
  required String remote,
  required String local,
}) {
  if (local == remote) return local;
  if (local == base) return remote;
  if (remote == base) return local;
  if (base.isEmpty) {
    if (remote.isEmpty) return local;
    if (local.isEmpty) return remote;
    if (remote.contains(local)) return remote;
    if (local.contains(remote)) return local;
    return '$remote\n$local';
  }

  final baseLines = base.split('\n');
  final remoteLines = remote.split('\n');
  final localLines = local.split('\n');

  final remoteHunks = _diffHunks(baseLines, remoteLines);
  final localHunks = _diffHunks(baseLines, localLines);

  final out = <String>[];
  var basePos = 0;
  var ri = 0;
  var li = 0;

  while (ri < remoteHunks.length || li < localHunks.length) {
    final rHunk = ri < remoteHunks.length ? remoteHunks[ri] : null;
    final lHunk = li < localHunks.length ? localHunks[li] : null;

    if (rHunk != null &&
        (lHunk == null || rHunk.baseEnd <= lHunk.baseStart) &&
        (lHunk == null || rHunk.baseStart < lHunk.baseStart || rHunk.baseEnd < lHunk.baseStart)) {
      out.addAll(baseLines.sublist(basePos, rHunk.baseStart));
      out.addAll(rHunk.replacement);
      basePos = rHunk.baseEnd;
      ri++;
    } else if (lHunk != null &&
        (rHunk == null || lHunk.baseEnd <= rHunk.baseStart) &&
        (rHunk == null || lHunk.baseStart < rHunk.baseStart || lHunk.baseEnd < rHunk.baseStart)) {
      out.addAll(baseLines.sublist(basePos, lHunk.baseStart));
      out.addAll(lHunk.replacement);
      basePos = lHunk.baseEnd;
      li++;
    } else {
      // Overlapping hunks (both edited the same region).
      final start = rHunk!.baseStart < lHunk!.baseStart
          ? rHunk.baseStart
          : lHunk.baseStart;
      var end = rHunk.baseEnd > lHunk.baseEnd ? rHunk.baseEnd : lHunk.baseEnd;

      out.addAll(baseLines.sublist(basePos, start));

      final rCombined = <String>[];
      final lCombined = <String>[];
      while (ri < remoteHunks.length && remoteHunks[ri].baseStart <= end) {
        final h = remoteHunks[ri++];
        if (h.baseEnd > end) end = h.baseEnd;
        rCombined.addAll(h.replacement);
      }
      while (li < localHunks.length && localHunks[li].baseStart <= end) {
        final h = localHunks[li++];
        if (h.baseEnd > end) end = h.baseEnd;
        lCombined.addAll(h.replacement);
      }

      if (_listEquals(rCombined, lCombined)) {
        out.addAll(rCombined);
      } else {
        out.addAll(rCombined);
        for (final line in lCombined) {
          if (!rCombined.contains(line)) {
            out.add(line);
          }
        }
      }
      basePos = end;
    }
  }

  if (basePos < baseLines.length) {
    out.addAll(baseLines.sublist(basePos));
  }
  return out.join('\n');
}

class _TextHunk {
  const _TextHunk(this.baseStart, this.baseEnd, this.replacement);

  final int baseStart;
  final int baseEnd;
  final List<String> replacement;
}

List<_TextHunk> _diffHunks(List<String> base, List<String> target) {
  final n = base.length;
  final m = target.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));

  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      if (base[i] == target[j]) {
        dp[i][j] = 1 + dp[i + 1][j + 1];
      } else {
        dp[i][j] = dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1];
      }
    }
  }

  final hunks = <_TextHunk>[];
  var i = 0;
  var j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && base[i] == target[j]) {
      i++;
      j++;
      continue;
    }
    final bStart = i;
    final tStart = j;
    while (i < n || j < m) {
      if (i < n && j < m && base[i] == target[j]) {
        break;
      }
      if (i < n && (j == m || dp[i + 1][j] >= dp[i][j + 1])) {
        i++;
      } else {
        j++;
      }
    }
    hunks.add(_TextHunk(bStart, i, target.sublist(tStart, j)));
  }
  return hunks;
}
