import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import 'package:photo_vault/core/widgets/base_screen_shell.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';
import '../../domain/entities/app_note.dart';
import '../../domain/repositories/notes_repository.dart';
import 'note_editor_screen.dart';

/// Displays private notes or the shared notes belonging to one chat.
class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    required this.notesRepository,
    required this.currentUserId,
    this.threadId,
  });

  final NotesRepository notesRepository;
  final String currentUserId;
  final String? threadId;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final _uuid = const Uuid();
  late final Stream<List<AppNote>> _notes;

  @override
  void initState() {
    super.initState();
    _notes = widget.threadId == null
        ? widget.notesRepository.watchPrivateNotes()
        : widget.notesRepository.watchThreadNotes(widget.threadId!);
  }

  Future<void> _createNewNote(NoteType type) async {
    final newNote = AppNote(
      id: _uuid.v4(),
      creatorId: widget.currentUserId,
      type: type,
      title: '',
      content: '',
      items: const [],
      createdAt: DateTime.now().toUtc(),
      updatedAt: DateTime.now().toUtc(),
    );

    try {
      await widget.notesRepository.savePrivateNote(newNote);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create note: $error')),
        );
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(
          note: newNote,
          notesRepository: widget.notesRepository,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  void _openNote(AppNote note) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(
          note: note,
          notesRepository: widget.notesRepository,
          currentUserId: widget.currentUserId,
        ),
      ),
    );
  }

  Future<void> _deleteNote(AppNote note) async {
    try {
      if (note.isShared) {
        await widget.notesRepository.deleteThreadNote(
          threadId: note.threadId!,
          noteId: note.id,
        );
      } else {
        await widget.notesRepository.deletePrivateNote(note.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete note: $error')),
        );
      }
    }
  }

  Future<void> _togglePin(AppNote note) async {
    final updated = note.copyWith(isPinned: !note.isPinned);
    try {
      if (updated.isShared) {
        await widget.notesRepository.saveThreadNote(updated);
      } else {
        await widget.notesRepository.savePrivateNote(updated);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not update pin: $error')));
      }
    }
  }

  void _showCreateOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_box_outlined,
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                  ),
                ),
                title: const Text('New Checklist'),
                subtitle: const Text('Add items you can check off and cut'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _createNewNote(NoteType.checklist);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.notes_rounded,
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                title: const Text('New Text Note'),
                subtitle: const Text('Plain text note for thoughts and info'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _createNewNote(NoteType.textNote);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final body = StreamBuilder<List<AppNote>>(
      stream: _notes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('Could not load notes: ${snapshot.error}'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final notes = [...snapshot.data!]..sort(_compareNotes);

        if (notes.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer.withValues(
                        alpha: 0.5,
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.checklist_rounded,
                      size: 36,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    widget.threadId == null
                        ? 'No private notes yet'
                        : 'No notes in this chat yet',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    widget.threadId == null
                        ? 'Create encrypted checklists and notes stored securely in your private vault.'
                        : 'Share a note or checklist from the attachment sheet.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return GridView.builder(
          padding: const EdgeInsets.all(AppSpacing.md),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
            childAspectRatio: 0.85,
          ),
          itemCount: notes.length,
          itemBuilder: (context, index) {
            final note = notes[index];
            return _NoteGridCard(
              note: note,
              onTap: () => _openNote(note),
              onPinToggle: () => _togglePin(note),
              onDelete:
                  widget.threadId == null ||
                      note.creatorId == widget.currentUserId
                  ? () => _deleteNote(note)
                  : null,
            );
          },
        );
      },
    );
    if (widget.threadId != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Chat Notes & Lists')),
        body: body,
      );
    }
    return BaseScreenShell(
      title: 'Notes & Lists',
      drawerSelectedIndex: 4,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateOptions(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create'),
      ),
      body: body,
    );
  }
}

int _compareNotes(AppNote a, AppNote b) {
  if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
  return b.updatedAt.compareTo(a.updatedAt);
}

class _NoteGridCard extends StatelessWidget {
  const _NoteGridCard({
    required this.note,
    required this.onTap,
    required this.onPinToggle,
    required this.onDelete,
  });

  final AppNote note;
  final VoidCallback onTap;
  final VoidCallback onPinToggle;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isChecklist = note.isChecklist;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isChecklist
                        ? Icons.check_box_outlined
                        : Icons.notes_rounded,
                    size: 16,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  if (note.isPinned) ...[
                    Icon(
                      Icons.push_pin_rounded,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                  ],
                  Expanded(
                    child: Text(
                      note.title.isNotEmpty ? note.title : 'Untitled',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onSelected: (val) {
                      if (val == 'pin' || val == 'unpin') onPinToggle();
                      if (val == 'delete') onDelete?.call();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: note.isPinned ? 'unpin' : 'pin',
                        child: Text(note.isPinned ? 'Unpin' : 'Pin'),
                      ),
                      if (onDelete != null)
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: isChecklist
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final item in note.items.take(4))
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 1),
                              child: Row(
                                children: [
                                  Icon(
                                    item.isDone
                                        ? Icons.check_box_rounded
                                        : Icons.check_box_outline_blank_rounded,
                                    size: 14,
                                    color: item.isDone
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      item.text,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            decoration: item.isDone
                                                ? TextDecoration.lineThrough
                                                : null,
                                            color: item.isDone
                                                ? theme
                                                      .colorScheme
                                                      .onSurfaceVariant
                                                      .withValues(alpha: 0.6)
                                                : theme.colorScheme.onSurface,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (note.items.length > 4)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                '+${note.items.length - 4} more',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      )
                    : Text(
                        note.content,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Edited ${DateFormat('d MMM yyyy, h:mm a').format(note.updatedAt.toLocal())}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
