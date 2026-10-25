import 'package:flutter/material.dart';
import '../../domain/entities/app_note.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/notes_repository.dart';
import '../screens/note_editor_screen.dart';
import 'package:photo_vault/core/presentation/theme/app_spacing.dart';

/// Interactive chat bubble displaying a shared note or checklist.
class SharedNoteBubble extends StatefulWidget {
  const SharedNoteBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.currentUserId,
    required this.notesRepository,
  });

  final ChatMessage message;
  final bool isMine;
  final String currentUserId;
  final NotesRepository notesRepository;

  @override
  State<SharedNoteBubble> createState() => _SharedNoteBubbleState();
}

class _SharedNoteBubbleState extends State<SharedNoteBubble> {
  AppNote? _note;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final noteId = widget.message.sharedNoteId;
    if (noteId == null || noteId.isEmpty) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    final note = await widget.notesRepository.getThreadNote(
      threadId: widget.message.threadId,
      noteId: noteId,
    );
    if (!mounted) return;
    setState(() {
      _note = note;
      _loading = false;
    });
  }

  void _openEditor() {
    final note = _note;
    if (note == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditorScreen(
          note: note,
          notesRepository: widget.notesRepository,
          currentUserId: widget.currentUserId,
          onNoteSaved: (AppNote updated) {
            if (mounted) {
              setState(() => _note = updated);
            }
          },
        ),
      ),
    );
  }

  void _toggleItem(ChecklistItem item) async {
    final note = _note;
    if (note == null) return;

    final nextDone = !item.isDone;
    final updatedItems = note.items.map((i) {
      if (i.id == item.id) {
        return i.copyWith(
          isDone: nextDone,
          completedAt: nextDone ? DateTime.now().toUtc() : null,
          completedBy: nextDone ? widget.currentUserId : null,
        );
      }
      return i;
    }).toList();

    final updatedNote = note.copyWith(
      items: updatedItems,
      updatedAt: DateTime.now().toUtc(),
      lastEditedBy: widget.currentUserId,
    );

    setState(() => _note = updatedNote);
    await widget.notesRepository.saveThreadNote(updatedNote);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = _note;

    if (_loading) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        width: 240,
        child: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.sm),
            Text('Loading note…'),
          ],
        ),
      );
    }

    if (note == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        width: 240,
        child: Row(
          children: [
            Icon(Icons.notes_rounded, color: theme.colorScheme.error, size: 20),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(child: Text('Note unavailable')),
          ],
        ),
      );
    }

    final isChecklist = note.isChecklist;
    final completed = note.completedCount;
    final total = note.totalCount;
    final progress = total > 0 ? (completed / total) : 0.0;

    return InkWell(
      onTap: _openEditor,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isChecklist
                        ? Icons.checklist_rounded
                        : Icons.note_alt_rounded,
                    size: 16,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
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
                Icon(
                  Icons.open_in_new_rounded,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (isChecklist) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 5,
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '$completed of $total items checked',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              // Show preview of up to 3 items
              for (final item in note.items.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => _toggleItem(item),
                        child: Icon(
                          item.isDone
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 16,
                          color: item.isDone
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          item.text,
                          style: theme.textTheme.bodySmall?.copyWith(
                            decoration:
                                item.isDone ? TextDecoration.lineThrough : null,
                            color: item.isDone
                                ? theme.colorScheme.onSurfaceVariant
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
              if (note.items.length > 3)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '+${note.items.length - 3} more items',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ] else ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                note.content.isNotEmpty
                    ? note.content
                    : 'Tap to write note…',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
