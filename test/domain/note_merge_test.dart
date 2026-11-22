import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/domain/entities/app_note.dart';
import 'package:photo_vault/features/chat/domain/entities/note_merge.dart';

AppNote _textNote({
  String title = 'Title',
  String content = '',
  DateTime? updatedAt,
  String? lastEditedBy,
}) => AppNote(
  id: 'n1',
  threadId: 't1',
  creatorId: 'u1',
  type: NoteType.textNote,
  title: title,
  content: content,
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: updatedAt ?? DateTime.utc(2024, 1, 1),
  lastEditedBy: lastEditedBy,
);

AppNote _checklistNote({
  String title = 'List',
  List<ChecklistItem> items = const [],
  DateTime? updatedAt,
}) => AppNote(
  id: 'n2',
  threadId: 't1',
  creatorId: 'u1',
  type: NoteType.checklist,
  title: title,
  items: items,
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: updatedAt ?? DateTime.utc(2024, 1, 1),
);

void main() {
  test('merges non-overlapping text note lines from both users', () {
    final base = _textNote(content: 'Line 1\nLine 2\nLine 3');
    final remote = _textNote(
      content: 'Line 1 (remote)\nLine 2\nLine 3',
      updatedAt: DateTime.utc(2024, 1, 2),
      lastEditedBy: 'u2',
    );
    final local = _textNote(
      content: 'Line 1\nLine 2\nLine 3 (local)',
      updatedAt: DateTime.utc(2024, 1, 3),
      lastEditedBy: 'u1',
    );

    final merged = mergeAppNotes(base: base, remote: remote, local: local);
    expect(merged.content, 'Line 1 (remote)\nLine 2\nLine 3 (local)');
  });

  test('preserves both additions when same text line is edited differently', () {
    final base = _textNote(content: 'Shared line');
    final remote = _textNote(
      content: 'Remote version',
      updatedAt: DateTime.utc(2024, 1, 2),
    );
    final local = _textNote(
      content: 'Local version',
      updatedAt: DateTime.utc(2024, 1, 3),
    );

    final merged = mergeAppNotes(base: base, remote: remote, local: local);
    expect(merged.content, contains('Remote version'));
    expect(merged.content, contains('Local version'));
  });

  test('merges concurrent checklist additions and toggles without loss', () {
    final base = _checklistNote(
      items: const [
        ChecklistItem(id: '1', text: 'Milk'),
        ChecklistItem(id: '2', text: 'Eggs'),
      ],
    );
    final remote = _checklistNote(
      items: const [
        ChecklistItem(id: '1', text: 'Milk', isDone: true),
        ChecklistItem(id: '2', text: 'Eggs'),
        ChecklistItem(id: '3', text: 'Bread'),
      ],
      updatedAt: DateTime.utc(2024, 1, 2),
    );
    final local = _checklistNote(
      items: const [
        ChecklistItem(id: '1', text: 'Milk'),
        ChecklistItem(id: '2', text: 'Organic Eggs'),
        ChecklistItem(id: '4', text: 'Butter'),
      ],
      updatedAt: DateTime.utc(2024, 1, 3),
    );

    final merged = mergeAppNotes(base: base, remote: remote, local: local);
    expect(merged.items.map((i) => i.id), ['1', '2', '3', '4']);
    expect(merged.items[0].isDone, isTrue);
    expect(merged.items[1].text, 'Organic Eggs');
    expect(merged.items[2].text, 'Bread');
    expect(merged.items[3].text, 'Butter');
  });

  test('keeps modified item if the other user deleted it', () {
    final base = _checklistNote(
      items: const [ChecklistItem(id: '1', text: 'Task')],
    );
    final remote = _checklistNote(
      items: const [],
      updatedAt: DateTime.utc(2024, 1, 2),
    );
    final local = _checklistNote(
      items: const [ChecklistItem(id: '1', text: 'Task updated locally')],
      updatedAt: DateTime.utc(2024, 1, 3),
    );

    final merged = mergeAppNotes(base: base, remote: remote, local: local);
    expect(merged.items.single.text, 'Task updated locally');
  });
}
