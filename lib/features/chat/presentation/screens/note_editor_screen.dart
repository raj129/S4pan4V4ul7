import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../domain/entities/app_note.dart';
import '../../domain/repositories/notes_repository.dart';
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

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  late TextEditingController _titleCtrl;
  late TextEditingController _contentCtrl;
  late AppNote _currentNote;
  final _uuid = const Uuid();
  final Map<String, FocusNode> _itemFocusNodes = {};
  Timer? _debounceTimer;
  StreamSubscription<List<AppNote>>? _threadNotesSub;
  bool _isSaving = false;
  bool _showCompletedSection = true;
  int _editRevision = 0;
  int _savesInProgress = 0;
  Future<void> _saveTail = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _currentNote = widget.note;
    if (_currentNote.isChecklist &&
        !_currentNote.items.any((item) => item.text.trim().isEmpty)) {
      _currentNote = _currentNote.copyWith(
        items: [..._currentNote.items, _emptyChecklistItem()],
      );
    }
    _titleCtrl = TextEditingController(text: _currentNote.title);
    _contentCtrl = TextEditingController(text: _currentNote.content);

    // If shared note, listen to real-time changes from other user
    if (_currentNote.isShared && _currentNote.threadId != null) {
      _threadNotesSub = widget.notesRepository
          .watchThreadNotes(_currentNote.threadId!)
          .listen((notes) {
            final remote = notes
                .where((n) => n.id == _currentNote.id)
                .firstOrNull;
            if (remote != null &&
                _debounceTimer == null &&
                !_isSaving &&
                remote.updatedAt.isAfter(_currentNote.updatedAt) &&
                remote.lastEditedBy != widget.currentUserId) {
              if (!mounted) return;
              setState(() {
                _currentNote = remote;
                if (_titleCtrl.text != remote.title) {
                  _titleCtrl.text = remote.title;
                }
                if (_contentCtrl.text != remote.content) {
                  _contentCtrl.text = remote.content;
                }
              });
            }
          });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _threadNotesSub?.cancel();
    for (final node in _itemFocusNodes.values) {
      node.dispose();
    }
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  void _triggerSave({bool immediate = false}) {
    _editRevision++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
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
    _savesInProgress++;
    setState(() => _isSaving = true);
    final revision = _editRevision;
    final updated = _currentNote.copyWith(
      title: _titleCtrl.text.trim(),
      content: _contentCtrl.text,
      items: _currentNote.items
          .where((item) => item.text.trim().isNotEmpty)
          .toList(),
      updatedAt: DateTime.now().toUtc(),
      lastEditedBy: widget.currentUserId,
    );
    final previous = _saveTail;
    final operation = previous.then((_) async {
      if (updated.isShared) {
        await widget.notesRepository.saveThreadNote(updated);
      } else {
        await widget.notesRepository.savePrivateNote(updated);
      }
    });
    _saveTail = operation.then((_) {}, onError: (Object _) {});
    try {
      await operation;
      if (!mounted) return true;
      _currentNote = _currentNote.copyWith(updatedAt: updated.updatedAt);
      widget.onNoteSaved?.call(updated);
      if (closeAfter) {
        if (revision != _editRevision) {
          return _save(closeAfter: true);
        }
        Navigator.of(context).pop();
      }
      return true;
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

  void _toggleType() {
    final nextType = _currentNote.type == NoteType.checklist
        ? NoteType.textNote
        : NoteType.checklist;

    List<ChecklistItem> nextItems = _currentNote.items;
    if (nextType == NoteType.checklist && nextItems.isEmpty) {
      final lines = _contentCtrl.text.split('\n');
      nextItems = lines
          .where((l) => l.trim().isNotEmpty)
          .map((l) => ChecklistItem(id: _uuid.v4(), text: l.trim()))
          .toList();
    }
    if (nextType == NoteType.checklist &&
        !nextItems.any((item) => item.text.trim().isEmpty)) {
      nextItems = [...nextItems, _emptyChecklistItem()];
    }

    setState(() {
      _currentNote = _currentNote.copyWith(type: nextType, items: nextItems);
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
          IconButton(
            tooltip: _currentNote.isChecklist
                ? 'Switch to text note'
                : 'Switch to checklist',
            icon: Icon(
              _currentNote.isChecklist
                  ? Icons.notes_rounded
                  : Icons.check_box_outlined,
            ),
            onPressed: _toggleType,
          ),
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              child: TextField(
                controller: _titleCtrl,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  hintText: 'Title',
                  hintStyle: theme.textTheme.titleLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.6,
                    ),
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
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Expanded(
              child: _currentNote.isChecklist
                  ? _buildChecklistBody(theme, uncompleted, completed)
                  : _buildTextNoteBody(theme),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextNoteBody(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: TextField(
        controller: _contentCtrl,
        maxLines: null,
        expands: true,
        style: theme.textTheme.bodyLarge,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          hintText: 'Type your note here…',
          hintStyle: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => _triggerSave(),
      ),
    );
  }

  Widget _buildChecklistBody(
    ThemeData theme,
    List<ChecklistItem> uncompleted,
    List<ChecklistItem> completed,
  ) {
    Widget reorderableItems(List<ChecklistItem> items, bool isCompleted) {
      return ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: items.length,
        onReorderItem: (oldIndex, newIndex) =>
            _reorderChecklistItems(items, isCompleted, oldIndex, newIndex),
        itemBuilder: (context, index) {
          final item = items[index];
          return _ChecklistItemRow(
            key: ValueKey('drag-${item.id}'),
            item: item,
            index: index,
            focusNode: _focusNodeFor(item.id),
            onToggle: () => _toggleChecklistItem(item),
            onChanged: (text) => _updateChecklistItemText(item, text),
            onSubmitted: () => _insertChecklistItemAfter(item),
            onBackspaceEmpty: () => _removeEmptyChecklistItem(item),
            onDelete: () => _deleteChecklistItem(item),
          );
        },
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        // Active uncompleted items
        reorderableItems(uncompleted, false),

        // Completed / checked items section (Google Keep style)
        if (completed.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Divider(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
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
          if (_showCompletedSection) reorderableItems(completed, true),
        ],
      ],
    );
  }
}

class _ChecklistItemRow extends StatefulWidget {
  const _ChecklistItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.focusNode,
    required this.onToggle,
    required this.onChanged,
    required this.onSubmitted,
    required this.onBackspaceEmpty,
    required this.onDelete,
  });

  final ChecklistItem item;
  final int index;
  final FocusNode focusNode;
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
  }

  @override
  void didUpdateWidget(covariant _ChecklistItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.text != widget.item.text &&
        _controller.text != widget.item.text) {
      _controller.text = widget.item.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = widget.item.isDone;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Checkbox(
            value: isDone,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
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
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: widget.onChanged,
              ),
            ),
          ),
          ReorderableDelayedDragStartListener(
            key: ValueKey('drag-handle-${widget.item.id}'),
            index: widget.index,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.drag_handle_rounded,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.45,
                ),
              ),
            ),
          ),
          IconButton(
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            tooltip: 'Remove item',
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
