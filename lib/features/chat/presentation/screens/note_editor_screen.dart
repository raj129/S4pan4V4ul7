import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/app_note.dart';
import '../../domain/entities/note_merge.dart';
import '../../domain/repositories/notes_repository.dart';
import '../widgets/rich_note_controller.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';

/// Interactive note & checklist editor with Google Keep-style checked
/// strikethrough styling, item ordering, and debounced auto-sync.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({
    super.key,
    required this.note,
    required this.notesRepository,
    required this.currentUserId,
    this.onNoteSaved,
  });

  final AppNote note;
  final NotesRepository notesRepository;
  final String currentUserId;
  final ValueChanged<AppNote>? onNoteSaved;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen>
    with WidgetsBindingObserver {
  late TextEditingController _titleCtrl;
  late RichNoteTextEditingController _contentCtrl;
  late TextEditingValue _previousContentValue;
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _contentFocusNode = FocusNode();
  late AppNote _currentNote;
  late AppNote _baseNote;
  final _uuid = const Uuid();
  final Map<String, FocusNode> _itemFocusNodes = {};
  Timer? _debounceTimer;
  Timer? _presenceThrottleTimer;
  StreamSubscription<AppNote?>? _threadNoteSub;
  Stream<List<NoteEditorPresence>>? _notePresencesStream;
  Timer? _editingHeartbeat;
  Future<void> _presenceWrite = Future<void>.value();
  bool _isSaving = false;
  bool _isDeletedRemotely = false;
  bool _hasSeenRemoteNote = false;
  bool _showCompletedSection = true;
  int _editRevision = 0;
  int _savedRevision = 0;
  int _savesInProgress = 0;
  Future<void> _saveTail = Future<void>.value();

  String? _activeTarget;
  String? _activeItemId;
  int? _activeLine;
  int? _activeCursorOffset;

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
    _baseNote = widget.note.copyWith(
      items: widget.note.items
          .where((item) => item.text.trim().isNotEmpty)
          .toList(),
    );
    _titleCtrl = TextEditingController(text: _currentNote.title);
    _contentCtrl = RichNoteTextEditingController.fromMarkdown(
      _currentNote.content,
    );
    _previousContentValue = _contentCtrl.value;

    _titleFocusNode.addListener(_onTitleFocusOrSelectionChanged);
    _titleCtrl.addListener(_onTitleFocusOrSelectionChanged);
    _contentFocusNode.addListener(_onContentFocusOrSelectionChanged);
    _contentCtrl.addListener(_onContentFocusOrSelectionChanged);

    // If shared note, listen to real-time changes from other user
    if (_currentNote.isShared && _currentNote.threadId != null) {
      _notePresencesStream = widget.notesRepository
          .watchThreadNoteEditorPresences(
            threadId: _currentNote.threadId!,
            noteId: _currentNote.id,
          );
      WidgetsBinding.instance.addObserver(this);
      _renewEditingPresence();
      _editingHeartbeat = Timer.periodic(
        const Duration(seconds: 12),
        (_) => _renewEditingPresence(),
      );
      _threadNoteSub = widget.notesRepository
          .watchThreadNote(
            threadId: _currentNote.threadId!,
            noteId: _currentNote.id,
          )
          .listen(_handleRemoteNoteEvent);
    }
  }

  void _handleRemoteNoteEvent(AppNote? remote) {
    if (!mounted) return;
    if (remote == null) {
      if (_hasSeenRemoteNote) {
        _debounceTimer?.cancel();
        _debounceTimer = null;
        setState(() => _isDeletedRemotely = true);
      }
      return;
    }

    _hasSeenRemoteNote = true;
    if (_isDeletedRemotely) {
      setState(() => _isDeletedRemotely = false);
    }

    if (remote == _baseNote) return;

    final hasPendingLocal =
        _debounceTimer != null || _isSaving || _editRevision != _savedRevision;
    final localSnapshot = _buildNoteSnapshot();
    final merged = hasPendingLocal
        ? mergeAppNotes(
            base: _baseNote,
            remote: remote,
            local: localSnapshot,
          )
        : remote;

    _baseNote = remote;
    _applyMergedNoteToState(merged);
  }

  void _applyMergedNoteToState(AppNote merged) {
    final localEmptyItems = merged.isChecklist
        ? _currentNote.items
              .where((item) => item.text.trim().isEmpty)
              .toList()
        : const <ChecklistItem>[];
    final nextItems = merged.isChecklist
        ? [
            ...merged.items,
            for (final empty in localEmptyItems)
              if (!merged.items.any((i) => i.id == empty.id)) empty,
          ]
        : merged.items;

    setState(() {
      _currentNote = merged.copyWith(items: nextItems);
      _setControllerTextPreservingSelection(_titleCtrl, merged.title);
      if (merged.content != _contentCtrl.toMarkdown()) {
        _contentCtrl.setFromMarkdown(merged.content);
        _previousContentValue = _contentCtrl.value;
      }
    });
  }

  void _setControllerTextPreservingSelection(
    TextEditingController controller,
    String nextText,
  ) {
    if (controller.text == nextText) return;
    final prevSelection = controller.selection;
    final maxOffset = nextText.length;
    final nextSelection = prevSelection.isValid
        ? TextSelection(
            baseOffset: prevSelection.baseOffset.clamp(0, maxOffset),
            extentOffset: prevSelection.extentOffset.clamp(0, maxOffset),
          )
        : TextSelection.collapsed(offset: maxOffset);
    controller.value = TextEditingValue(
      text: nextText,
      selection: nextSelection,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _editingHeartbeat?.cancel();
    _presenceThrottleTimer?.cancel();
    if (_debounceTimer != null && !_isDeletedRemotely) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      unawaited(_persistSnapshot(_buildNoteSnapshot(), _editRevision));
    }
    _releaseEditingPresence();
    _threadNoteSub?.cancel();
    _titleFocusNode.removeListener(_onTitleFocusOrSelectionChanged);
    _titleCtrl.removeListener(_onTitleFocusOrSelectionChanged);
    _contentFocusNode.removeListener(_onContentFocusOrSelectionChanged);
    _contentCtrl.removeListener(_onContentFocusOrSelectionChanged);
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _renewEditingPresence();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _releaseEditingPresence();
    }
  }

  void _onTitleFocusOrSelectionChanged() {
    if (!_titleFocusNode.hasFocus) return;
    final offset = _titleCtrl.selection.isValid
        ? _titleCtrl.selection.baseOffset
        : _titleCtrl.text.length;
    _schedulePresenceUpdate(
      target: 'title',
      itemId: null,
      line: null,
      cursorOffset: offset < 0 ? 0 : offset,
    );
  }

  void _onContentFocusOrSelectionChanged() {
    if (!_contentFocusNode.hasFocus) return;
    final text = _contentCtrl.text;
    final rawOffset = _contentCtrl.selection.isValid
        ? _contentCtrl.selection.baseOffset
        : text.length;
    final offset = rawOffset.clamp(0, text.length);
    final line = '\n'.allMatches(text.substring(0, offset)).length;
    _schedulePresenceUpdate(
      target: 'content',
      itemId: null,
      line: line,
      cursorOffset: offset,
    );
  }

  void _onChecklistItemFocusOrSelection(String itemId, int cursorOffset) {
    _schedulePresenceUpdate(
      target: 'item',
      itemId: itemId,
      line: null,
      cursorOffset: cursorOffset < 0 ? 0 : cursorOffset,
    );
  }

  void _schedulePresenceUpdate({
    required String target,
    required String? itemId,
    required int? line,
    required int? cursorOffset,
  }) {
    if (!_currentNote.isShared || _currentNote.threadId == null) return;
    final changed =
        _activeTarget != target ||
        _activeItemId != itemId ||
        _activeLine != line ||
        _activeCursorOffset != cursorOffset;
    if (!changed) return;

    _activeTarget = target;
    _activeItemId = itemId;
    _activeLine = line;
    _activeCursorOffset = cursorOffset;

    _presenceThrottleTimer?.cancel();
    _presenceThrottleTimer = Timer(
      const Duration(milliseconds: 250),
      _renewEditingPresence,
    );
  }

  void _renewEditingPresence() {
    final threadId = _currentNote.threadId;
    if (!_currentNote.isShared || threadId == null || _isDeletedRemotely) {
      return;
    }
    _presenceWrite = _presenceWrite
        .then(
          (_) => widget.notesRepository.setThreadNoteEditing(
            threadId: threadId,
            noteId: _currentNote.id,
            uid: widget.currentUserId,
            isEditing: true,
            editingTarget: _activeTarget,
            editingItemId: _activeItemId,
            editingLine: _activeLine,
            cursorOffset: _activeCursorOffset,
          ),
        )
        .catchError((Object error) {
          debugPrint('Could not renew shared note edit presence: $error');
        });
  }

  void _releaseEditingPresence() {
    final threadId = _currentNote.threadId;
    if (!_currentNote.isShared || threadId == null) return;
    _presenceWrite = _presenceWrite
        .then(
          (_) => widget.notesRepository.setThreadNoteEditing(
            threadId: threadId,
            noteId: _currentNote.id,
            uid: widget.currentUserId,
            isEditing: false,
          ),
        )
        .catchError((Object error) {
          debugPrint('Could not release shared note edit presence: $error');
        });
  }

  AppNote _buildNoteSnapshot() => _currentNote.copyWith(
    title: _titleCtrl.text.trim(),
    content: _contentCtrl.toMarkdown(),
    items: _currentNote.items
        .where((item) => item.text.trim().isNotEmpty)
        .toList(),
    updatedAt: DateTime.now().toUtc(),
    lastEditedBy: widget.currentUserId,
  );

  Future<AppNote> _persistSnapshot(AppNote snapshot, int revision) {
    final previous = _saveTail;
    final operation = previous.then((_) async {
      if (snapshot.isShared) {
        return widget.notesRepository.saveThreadNote(
          snapshot,
          baseNote: _baseNote,
        );
      } else {
        await widget.notesRepository.savePrivateNote(snapshot);
        return snapshot;
      }
    });
    _saveTail = operation.then((_) {}, onError: (Object _) {});
    return operation.then((saved) {
      _savedRevision = revision > _savedRevision ? revision : _savedRevision;
      return saved;
    });
  }

  Future<void> _saveCopyToPrivateNotes() async {
    final copy = _buildNoteSnapshot().copyWith(
      id: _uuid.v4(),
      threadId: null,
      creatorId: widget.currentUserId,
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
      lastEditedBy: widget.currentUserId,
    );
    await widget.notesRepository.savePrivateNote(
      AppNote(
        id: copy.id,
        threadId: null,
        creatorId: widget.currentUserId,
        type: copy.type,
        title: copy.title.isNotEmpty ? '${copy.title} (Copy)' : 'Deleted note copy',
        content: copy.content,
        items: copy.items,
        createdAt: copy.createdAt,
        updatedAt: copy.updatedAt,
        lastEditedBy: widget.currentUserId,
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved a copy to Private Notes')),
    );
    Navigator.of(context).pop();
  }

  void _triggerSave({bool immediate = false}) {
    _editRevision++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_isDeletedRemotely) return;
    if (immediate) {
      unawaited(_save());
    } else {
      _debounceTimer = Timer(const Duration(milliseconds: 600), () {
        _debounceTimer = null;
        unawaited(_save());
      });
    }
  }

  Future<bool> _save({bool closeAfter = false}) async {
    if (!mounted) return false;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_isDeletedRemotely) {
      if (closeAfter) Navigator.of(context).pop();
      return false;
    }
    _savesInProgress++;
    setState(() => _isSaving = true);
    final revision = _editRevision;
    final updated = _buildNoteSnapshot();
    try {
      final saved = await _persistSnapshot(updated, revision);
      if (!mounted) return true;
      _baseNote = saved;
      if (revision == _editRevision) {
        _applyMergedNoteToState(saved);
      } else {
        _currentNote = _currentNote.copyWith(updatedAt: saved.updatedAt);
      }
      widget.onNoteSaved?.call(saved);
      if (closeAfter) {
        if (revision != _editRevision) {
          return await _save(closeAfter: true);
        }
        Navigator.of(context).pop();
      }
      return true;
    } on NoteDeletedException {
      if (mounted) {
        setState(() => _isDeletedRemotely = true);
      }
      return false;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save note: $e')));
      }
      return false;
    } finally {
      _savesInProgress--;
      if (mounted) setState(() => _isSaving = _savesInProgress > 0);
    }
  }

  void _toggleChecklistItem(ChecklistItem item) {
    final nextDone = !item.isDone;
    final updatedItems = _currentNote.items.map((i) {
      if (i.id == item.id) {
        return i.copyWith(
          isDone: nextDone,
          completedAt: nextDone ? DateTime.now().toUtc() : null,
          completedBy: nextDone ? widget.currentUserId : null,
        );
      }
      return i;
    }).toList();

    setState(() {
      _currentNote = _currentNote.copyWith(items: updatedItems);
    });
    // Checkbox toggling syncs immediately
    _triggerSave(immediate: true);
  }

  ChecklistItem _emptyChecklistItem() =>
      ChecklistItem(id: _uuid.v4(), text: '');

  FocusNode _focusNodeFor(String itemId) =>
      _itemFocusNodes.putIfAbsent(itemId, FocusNode.new);

  void _focusChecklistItem(String itemId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodeFor(itemId).requestFocus();
    });
  }

  void _addChecklistItem() {
    final emptyItem = _currentNote.items
        .where((item) => !item.isDone && item.text.trim().isEmpty)
        .firstOrNull;
    if (emptyItem != null) {
      _focusChecklistItem(emptyItem.id);
      return;
    }

    final item = _emptyChecklistItem();
    setState(() {
      _currentNote = _currentNote.copyWith(
        items: [..._currentNote.items, item],
      );
    });
    _triggerSave();
    _focusChecklistItem(item.id);
  }

  void _insertChecklistItemAfter(ChecklistItem item) {
    final items = [..._currentNote.items];
    final index = items.indexWhere((candidate) => candidate.id == item.id);
    if (index < 0 || items[index].text.trim().isEmpty) return;
    final trailingEmpty = items.indexWhere(
      (candidate) => candidate.id != item.id && candidate.text.trim().isEmpty,
    );
    final next = trailingEmpty >= 0
        ? items.removeAt(trailingEmpty)
        : _emptyChecklistItem();
    final insertAt = items.indexWhere((candidate) => candidate.id == item.id);
    items.insert(insertAt + 1, next);
    setState(() {
      _currentNote = _currentNote.copyWith(items: items);
    });
    _triggerSave();
    _focusChecklistItem(next.id);
  }

  void _removeEmptyChecklistItem(ChecklistItem item) {
    if (item.text.trim().isNotEmpty) return;
    final active = _currentNote.items.where((i) => !i.isDone).toList();
    final index = active.indexWhere((candidate) => candidate.id == item.id);
    if (index <= 0) return;
    final previousId = active[index - 1].id;
    setState(() {
      _currentNote = _currentNote.copyWith(
        items: _currentNote.items.where((i) => i.id != item.id).toList(),
      );
    });
    _itemFocusNodes.remove(item.id)?.dispose();
    _triggerSave();
    _focusChecklistItem(previousId);
  }

  void _reorderChecklistItems(
    List<ChecklistItem> group,
    bool completedGroup,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex == newIndex) return;
    final reordered = [...group];
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    var groupIndex = 0;
    final items = _currentNote.items.map((item) {
      if (item.isDone == completedGroup) return reordered[groupIndex++];
      return item;
    }).toList();
    setState(() {
      _currentNote = _currentNote.copyWith(items: items);
    });
    _triggerSave(immediate: true);
  }

  void _updateChecklistItemText(ChecklistItem item, String newText) {
    final updatedItems = _currentNote.items.map((i) {
      if (i.id == item.id) {
        return i.copyWith(text: newText);
      }
      return i;
    }).toList();

    setState(() {
      _currentNote = _currentNote.copyWith(items: updatedItems);
    });
    _triggerSave();
  }

  void _deleteChecklistItem(ChecklistItem item) {
    _itemFocusNodes.remove(item.id)?.dispose();
    setState(() {
      _currentNote = _currentNote.copyWith(
        items: _currentNote.items.where((i) => i.id != item.id).toList(),
      );
    });
    _triggerSave(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final uncompleted = _currentNote.items.where((i) => !i.isDone).toList();
    final completed = _currentNote.items.where((i) => i.isDone).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentNote.isShared
              ? 'Shared ${_currentNote.isChecklist ? 'Checklist' : 'Note'}'
              : 'Private ${_currentNote.isChecklist ? 'Checklist' : 'Note'}',
          style: theme.textTheme.titleMedium,
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              tooltip: 'Save',
              icon: const Icon(Icons.check_rounded),
              onPressed: () => _save(closeAfter: true),
            ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<List<NoteEditorPresence>>(
          stream: _notePresencesStream,
          builder: (context, snapshot) {
            final remotePresences = (snapshot.data ?? const <NoteEditorPresence>[])
                .where((p) => p.userId != widget.currentUserId)
                .toList(growable: false);
            final titleEditedRemotely = remotePresences.any(
              (p) => p.editingTarget == 'title',
            );
            final contentPresence = remotePresences
                .where((p) => p.editingTarget == 'content')
                .firstOrNull;
            final remotelyEditedItemIds = remotePresences
                .where(
                  (p) =>
                      p.editingTarget == 'item' && p.editingItemId != null,
                )
                .map((p) => p.editingItemId!)
                .toSet();

            return Column(
              children: [
                if (_isDeletedRemotely)
                  MaterialBanner(
                    backgroundColor: theme.colorScheme.errorContainer,
                    content: Text(
                      'This note was deleted by the other participant. Your current text is still here.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: _saveCopyToPrivateNotes,
                        child: const Text('Save copy'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                if (remotePresences.isNotEmpty)
                  _buildPresenceBanner(theme, remotePresences),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.sm,
                    AppSpacing.lg,
                    AppSpacing.sm,
                  ),
                  child: Container(
                    decoration: titleEditedRemotely
                        ? BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: theme.colorScheme.primary,
                                width: 3,
                              ),
                            ),
                          )
                        : null,
                    padding: titleEditedRemotely
                        ? const EdgeInsets.only(left: AppSpacing.sm)
                        : EdgeInsets.zero,
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _titleCtrl,
                            focusNode: _titleFocusNode,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Title',
                              hintStyle: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant
                                    .withValues(alpha: 0.6),
                                fontWeight: FontWeight.w700,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (_) => _triggerSave(),
                          ),
                        ),
                        if (titleEditedRemotely)
                          _EditingBadge(theme: theme, label: 'Editing'),
                      ],
                    ),
                  ),
                ),
                Divider(
                  height: 1,
                  color: theme.colorScheme.outlineVariant.withValues(
                    alpha: 0.3,
                  ),
                ),
                Expanded(
                  child: _currentNote.isChecklist
                      ? _buildChecklistBody(
                          theme,
                          uncompleted,
                          completed,
                          remotelyEditedItemIds,
                        )
                      : _buildTextNoteBody(theme, contentPresence),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPresenceBanner(
    ThemeData theme,
    List<NoteEditorPresence> remotePresences,
  ) {
    final first = remotePresences.first;
    final detail = switch (first.editingTarget) {
      'title' => ' • Title',
      'content' when first.editingLine != null =>
        ' • Line ${first.editingLine! + 1}',
      'item' when first.editingItemId != null => () {
        final item = _currentNote.items
            .where((i) => i.id == first.editingItemId)
            .firstOrNull;
        if (item != null && item.text.trim().isNotEmpty) {
          return ' • "${item.text.trim()}"';
        }
        return ' • Checklist item';
      }(),
      _ => '',
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            Icons.edit_outlined,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              remotePresences.length == 1
                  ? 'Someone else is editing this note$detail'
                  : '${remotePresences.length} people are editing this note',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTextNoteBody(
    ThemeData theme,
    NoteEditorPresence? contentPresence,
  ) {
    final remoteLine = contentPresence?.editingLine;
    final lines = _contentCtrl.text.split('\n');
    final remoteLinePreview =
        (remoteLine != null && remoteLine >= 0 && remoteLine < lines.length)
        ? lines[remoteLine]
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (remoteLine != null)
          Container(
            margin: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              0,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(color: theme.colorScheme.primary, width: 3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.text_fields_rounded,
                  size: 14,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    remoteLinePreview != null && remoteLinePreview.isNotEmpty
                        ? 'Collaborator cursor at line ${remoteLine + 1}: "$remoteLinePreview"'
                        : 'Collaborator cursor at line ${remoteLine + 1}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: TextField(
              controller: _contentCtrl,
              focusNode: _contentFocusNode,
              maxLines: null,
              expands: true,
              style: theme.textTheme.bodyLarge,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: 'Type your note here…',
                hintStyle: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.6,
                  ),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) {
                _contentCtrl.handleListAutoArrange(
                  _previousContentValue,
                  _contentCtrl.value,
                );
                _previousContentValue = _contentCtrl.value;
                _triggerSave();
              },
            ),
          ),
        ),
        _buildDetectedLinksStrip(theme),
        _buildFormattingToolbar(theme),
      ],
    );
  }

  Widget _buildDetectedLinksStrip(ThemeData theme) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _contentCtrl,
      builder: (context, _, _) {
        final urls = _contentCtrl.extractActiveUrls();
        if (urls.isEmpty) return const SizedBox.shrink();
        final cs = theme.colorScheme;
        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: urls.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, index) {
              final url = urls[index];
              return ActionChip(
                avatar: Icon(Icons.open_in_new_rounded, size: 15, color: cs.primary),
                label: Text(
                  url.replaceFirst(RegExp(r'^https?://'), ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: () =>
                    unawaited(RichNoteTextEditingController.openNoteUrl(url)),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildFormattingToolbar(ThemeData theme) {
    final cs = theme.colorScheme;
    return ListenableBuilder(
      listenable: _contentCtrl,
      builder: (context, _) => Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          border: Border(
            top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              IconButton(
                tooltip: 'Bold',
                isSelected: _contentCtrl.isBoldActive,
                icon: const Icon(Icons.format_bold_rounded),
                onPressed: () => _applyFormatting(() {
                  _contentCtrl.toggleStyle(bold: true);
                }),
              ),
              IconButton(
                tooltip: 'Italic',
                isSelected: _contentCtrl.isItalicActive,
                icon: const Icon(Icons.format_italic_rounded),
                onPressed: () => _applyFormatting(() {
                  _contentCtrl.toggleStyle(italic: true);
                }),
              ),
              IconButton(
                tooltip: 'Strikethrough',
                isSelected: _contentCtrl.isStrikethroughActive,
                icon: const Icon(Icons.format_strikethrough_rounded),
                onPressed: () => _applyFormatting(() {
                  _contentCtrl.toggleStyle(strikethrough: true);
                }),
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Insert link',
                icon: const Icon(Icons.link_rounded),
                onPressed: _promptInsertLink,
              ),
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Bullet list',
                icon: const Icon(Icons.format_list_bulleted_rounded),
                onPressed: () => _applyFormatting(_contentCtrl.toggleBulletList),
              ),
              IconButton(
                tooltip: 'Numbered list',
                icon: const Icon(Icons.format_list_numbered_rounded),
                onPressed: () =>
                    _applyFormatting(_contentCtrl.toggleNumberedList),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _applyFormatting(VoidCallback action) {
    action();
    _previousContentValue = _contentCtrl.value;
    _triggerSave();
    if (!_contentFocusNode.hasFocus) {
      _contentFocusNode.requestFocus();
    }
  }

  Future<void> _promptInsertLink() async {
    final sel = _contentCtrl.selection;
    final initialLabel = (sel.isValid && sel.start != sel.end)
        ? _contentCtrl.text.substring(sel.start, sel.end)
        : '';
    final result = await showDialog<(String url, String label)>(
      context: context,
      builder: (_) => _InsertLinkDialog(initialLabel: initialLabel),
    );
    if (result == null || !mounted) return;
    _applyFormatting(() {
      _contentCtrl.insertLink(url: result.$1, label: result.$2);
    });
  }

  Widget _buildChecklistBody(
    ThemeData theme,
    List<ChecklistItem> uncompleted,
    List<ChecklistItem> completed,
    Set<String> remotelyEditedItemIds,
  ) {
    Widget reorderableSliver(List<ChecklistItem> items, bool isCompleted) {
      return SliverReorderableList(
        itemCount: items.length,
        onReorderItem: (oldIndex, newIndex) =>
            _reorderChecklistItems(items, isCompleted, oldIndex, newIndex),
        proxyDecorator: (child, index, animation) {
          return Material(
            elevation: 6,
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: child,
          );
        },
        itemBuilder: (context, index) {
          final item = items[index];
          return _ChecklistItemRow(
            key: ValueKey('drag-${item.id}'),
            item: item,
            index: index,
            focusNode: _focusNodeFor(item.id),
            isRemotelyEdited: remotelyEditedItemIds.contains(item.id),
            onFocusOrSelectionChanged: (offset) =>
                _onChecklistItemFocusOrSelection(item.id, offset),
            onToggle: () => _toggleChecklistItem(item),
            onChanged: (text) => _updateChecklistItemText(item, text),
            onSubmitted: () => _insertChecklistItemAfter(item),
            onBackspaceEmpty: () => _removeEmptyChecklistItem(item),
            onDelete: () => _deleteChecklistItem(item),
          );
        },
      );
    }

    return CustomScrollView(
      slivers: [
        const SliverPadding(padding: EdgeInsets.only(top: AppSpacing.sm)),
        // Active uncompleted items
        reorderableSliver(uncompleted, false),
        SliverToBoxAdapter(
          child: InkWell(
            onTap: _addChecklistItem,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.add_rounded,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'Add item',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Completed / checked items section (Google Keep style)
        if (completed.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.md),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  child: Divider(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _showCompletedSection = !_showCompletedSection;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _showCompletedSection
                              ? Icons.keyboard_arrow_down_rounded
                              : Icons.keyboard_arrow_right_rounded,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${completed.length} completed items',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_showCompletedSection) reorderableSliver(completed, true),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.lg)),
      ],
    );
  }
}

class _EditingBadge extends StatelessWidget {
  const _EditingBadge({required this.theme, required this.label});

  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ChecklistItemRow extends StatefulWidget {
  const _ChecklistItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.focusNode,
    required this.isRemotelyEdited,
    required this.onFocusOrSelectionChanged,
    required this.onToggle,
    required this.onChanged,
    required this.onSubmitted,
    required this.onBackspaceEmpty,
    required this.onDelete,
  });

  final ChecklistItem item;
  final int index;
  final FocusNode focusNode;
  final bool isRemotelyEdited;
  final ValueChanged<int> onFocusOrSelectionChanged;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final VoidCallback onBackspaceEmpty;
  final VoidCallback onDelete;

  @override
  State<_ChecklistItemRow> createState() => _ChecklistItemRowState();
}

class _ChecklistItemRowState extends State<_ChecklistItemRow> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.item.text);
    widget.focusNode.addListener(_handleFocusOrSelection);
    _controller.addListener(_handleFocusOrSelection);
  }

  void _handleFocusOrSelection() {
    if (!widget.focusNode.hasFocus) return;
    final offset = _controller.selection.isValid
        ? _controller.selection.baseOffset
        : _controller.text.length;
    widget.onFocusOrSelectionChanged(offset < 0 ? 0 : offset);
  }

  @override
  void didUpdateWidget(covariant _ChecklistItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusOrSelection);
      widget.focusNode.addListener(_handleFocusOrSelection);
    }
    if (oldWidget.item.text != widget.item.text &&
        _controller.text != widget.item.text) {
      final prev = _controller.selection;
      final maxOffset = widget.item.text.length;
      _controller.value = TextEditingValue(
        text: widget.item.text,
        selection: prev.isValid
            ? TextSelection(
                baseOffset: prev.baseOffset.clamp(0, maxOffset),
                extentOffset: prev.extentOffset.clamp(0, maxOffset),
              )
            : TextSelection.collapsed(offset: maxOffset),
      );
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusOrSelection);
    _controller.removeListener(_handleFocusOrSelection);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = widget.item.isDone;

    return Container(
      color: widget.isRemotelyEdited
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.24)
          : Colors.transparent,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ReorderableDragStartListener(
            key: ValueKey('drag-handle-${widget.item.id}'),
            index: widget.index,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.55,
                ),
              ),
            ),
          ),
          Checkbox(
            value: isDone,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
            visualDensity: VisualDensity.compact,
            onChanged: (_) => widget.onToggle(),
          ),
          Expanded(
            child: Focus(
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.backspace &&
                    _controller.text.isEmpty &&
                    _controller.selection.baseOffset <= 0) {
                  widget.onBackspaceEmpty();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _controller,
                focusNode: widget.focusNode,
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => widget.onSubmitted(),
                style: theme.textTheme.bodyLarge?.copyWith(
                  decoration: isDone ? TextDecoration.lineThrough : null,
                  color: isDone
                      ? theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.6,
                        )
                      : theme.colorScheme.onSurface,
                ),
                decoration: const InputDecoration(
                  hintText: 'List item',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ),
          if (widget.isRemotelyEdited)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _EditingBadge(theme: theme, label: 'Editing'),
            ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            tooltip: 'Remove item',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}

class _InsertLinkDialog extends StatefulWidget {
  const _InsertLinkDialog({required this.initialLabel});

  final String initialLabel;

  @override
  State<_InsertLinkDialog> createState() => _InsertLinkDialogState();
}

class _InsertLinkDialogState extends State<_InsertLinkDialog> {
  late final TextEditingController _urlCtrl = TextEditingController();
  late final TextEditingController _labelCtrl = TextEditingController(
    text: widget.initialLabel,
  );
  String? _error;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _labelCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Enter a URL.');
      return;
    }
    Navigator.of(context).pop((url, _labelCtrl.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.link_rounded),
      title: const Text('Insert link'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _urlCtrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              decoration: InputDecoration(
                labelText: 'URL',
                hintText: 'https://example.com',
                errorText: _error,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _labelCtrl,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(
                labelText: 'Display text (optional)',
                hintText: 'Link title',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Insert'),
        ),
      ],
    );
  }
}
