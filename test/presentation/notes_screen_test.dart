import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:photo_vault/core/widgets/app_navigation_drawer.dart';
import 'package:photo_vault/features/chat/domain/entities/app_note.dart';
import 'package:photo_vault/features/chat/domain/entities/chat_message.dart';
import 'package:photo_vault/features/chat/domain/entities/note_merge.dart';
import 'package:photo_vault/features/chat/domain/repositories/notes_repository.dart';
import 'package:photo_vault/features/chat/presentation/screens/note_editor_screen.dart';
import 'package:photo_vault/features/chat/presentation/screens/notes_screen.dart';
import 'package:photo_vault/features/chat/presentation/widgets/shared_note_bubble.dart';

class _NotesRepository implements NotesRepository {
  final private = <AppNote>[];
  final shared = <AppNote>[];
  final privateUpdates = StreamController<List<AppNote>>.broadcast();
  final sharedUpdates = StreamController<List<AppNote>>.broadcast();
  bool failSave = false;
  String? watchedThread;
  Completer<void>? nextPrivateSaveGate;
  final Map<String, Map<String, NoteEditorPresence>> editors = {};
  final Map<String, StreamController<List<NoteEditorPresence>>> editorUpdates =
      {};

  String _editorKey(String threadId, String noteId) => '$threadId/$noteId';

  @override
  Stream<List<AppNote>> watchPrivateNotes() async* {
    yield List.of(private);
    yield* privateUpdates.stream;
  }

  @override
  Stream<List<AppNote>> watchThreadNotes(String threadId) async* {
    watchedThread = threadId;
    yield List.of(shared);
    yield* sharedUpdates.stream;
  }

  @override
  Stream<AppNote?> watchThreadNote({
    required String threadId,
    required String noteId,
  }) async* {
    yield shared
        .where((n) => n.id == noteId && n.threadId == threadId)
        .firstOrNull;
    yield* sharedUpdates.stream.map(
      (notes) => notes
          .where((n) => n.id == noteId && n.threadId == threadId)
          .firstOrNull,
    );
  }

  @override
  Stream<List<String>> watchThreadNoteEditors({
    required String threadId,
    required String noteId,
  }) => watchThreadNoteEditorPresences(
    threadId: threadId,
    noteId: noteId,
  ).map((presences) => presences.map((p) => p.userId).toList(growable: false));

  @override
  Stream<List<NoteEditorPresence>> watchThreadNoteEditorPresences({
    required String threadId,
    required String noteId,
  }) async* {
    final key = _editorKey(threadId, noteId);
    yield List.of(editors[key]?.values ?? const <NoteEditorPresence>[]);
    yield* (editorUpdates[key] ??=
            StreamController<List<NoteEditorPresence>>.broadcast())
        .stream;
  }

  @override
  Future<void> setThreadNoteEditing({
    required String threadId,
    required String noteId,
    required String uid,
    required bool isEditing,
    String? editingTarget,
    String? editingItemId,
    int? editingLine,
    int? cursorOffset,
  }) async {
    final key = _editorKey(threadId, noteId);
    final active = editors.putIfAbsent(
      key,
      () => <String, NoteEditorPresence>{},
    );
    if (isEditing) {
      active[uid] = NoteEditorPresence(
        userId: uid,
        editingTarget: editingTarget,
        editingItemId: editingItemId,
        editingLine: editingLine,
        cursorOffset: cursorOffset,
      );
    } else {
      active.remove(uid);
    }
    editorUpdates[key]?.add(List.of(active.values));
  }

  @override
  Future<void> savePrivateNote(AppNote note) async {
    if (failSave) throw StateError('storage unavailable');
    final gate = nextPrivateSaveGate;
    nextPrivateSaveGate = null;
    if (gate != null) await gate.future;
    private.removeWhere((item) => item.id == note.id);
    private.add(note);
    privateUpdates.add(List.of(private));
  }

  @override
  Future<AppNote> saveThreadNote(AppNote note, {AppNote? baseNote}) async {
    if (failSave) throw StateError('network unavailable');
    final existingIndex = shared.indexWhere((item) => item.id == note.id);
    if (baseNote != null && existingIndex < 0) {
      throw NoteDeletedException(note.id);
    }
    final saved = existingIndex >= 0
        ? mergeAppNotes(base: baseNote, remote: shared[existingIndex], local: note)
        : note;
    shared.removeWhere((item) => item.id == note.id);
    shared.add(saved);
    sharedUpdates.add(List.of(shared));
    return saved;
  }

  @override
  Future<AppNote?> getThreadNote({
    required String threadId,
    required String noteId,
  }) async {
    for (final note in shared) {
      if (note.id == noteId && note.threadId == threadId) return note;
    }
    return null;
  }

  @override
  Future<void> deletePrivateNote(String noteId) async {
    private.removeWhere((note) => note.id == noteId);
    privateUpdates.add(List.of(private));
  }

  @override
  Future<void> deleteThreadNote({
    required String threadId,
    required String noteId,
  }) async {
    shared.removeWhere(
      (note) => note.id == noteId && note.threadId == threadId,
    );
    sharedUpdates.add(List.of(shared));
  }

  Future<void> close() async {
    await privateUpdates.close();
    await sharedUpdates.close();
    for (final controller in editorUpdates.values) {
      await controller.close();
    }
  }
}

AppNote _note(
  String title, {
  String? threadId,
  NoteType type = NoteType.textNote,
  DateTime? updatedAt,
}) => AppNote(
  id: title,
  threadId: threadId,
  creatorId: 'me',
  type: type,
  title: title,
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: updatedAt ?? DateTime.utc(2024, 1, 2, 9, 30),
);

AppNote _checklist(String title) => AppNote(
  id: title,
  creatorId: 'me',
  type: NoteType.checklist,
  title: title,
  items: [
    ChecklistItem(id: '$title-1', text: 'First'),
    ChecklistItem(id: '$title-2', text: 'Second'),
  ],
  createdAt: DateTime.utc(2024, 1, 1),
  updatedAt: DateTime.utc(2024, 1, 2),
);

Finder _emptyChecklistFields() => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      widget.decoration?.hintText == 'List item' &&
      widget.controller?.text.isEmpty == true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _NotesRepository repository;

  test('drawer destination routes match the visible order', () {
    expect(navigationPathForDestination(4), '/notes');
    expect(navigationPathForDestination(5), '/calls');
    expect(navigationPathForDestination(6), '/settings');
    expect(navigationPathForDestination(7), '/settings/developer');
    expect(navigationPathForDestination(8), '/chat/my-locations');
    expect(navigationPathForDestination(9), isNull);
  });

  setUp(() {
    repository = _NotesRepository();
  });
  tearDown(() => repository.close());

  testWidgets(
    'chat list shows only current chat, newest first with date and time',
    (tester) async {
      repository.shared.addAll([
        _note('Old', threadId: 'chat-1'),
        _note(
          'Recent',
          threadId: 'chat-1',
          updatedAt: DateTime.utc(2024, 5, 6, 15, 45),
        ),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: NotesScreen(
            notesRepository: repository,
            currentUserId: 'me',
            threadId: 'chat-1',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(repository.watchedThread, 'chat-1');
      expect(
        tester.getTopLeft(find.text('Recent')).dx,
        lessThan(tester.getTopLeft(find.text('Old')).dx),
      );
      expect(
        find.text(
          'Edited ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.utc(2024, 5, 6, 15, 45).toLocal())}',
        ),
        findsOneWidget,
      );
      expect(find.text('Create'), findsOneWidget);

      await tester.tap(find.text('Recent'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditorScreen), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextField, 'Title'),
        'Updated shared note',
      );
      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(
        repository.shared.where((note) => note.title == 'Updated shared note'),
        hasLength(1),
      );
      expect(repository.shared.last.threadId, 'chat-1');
      expect(find.byType(NoteEditorScreen), findsNothing);
    },
  );

  testWidgets('chat Create saves a shared note and posts it to the thread', (
    tester,
  ) async {
    final sharedNoteIds = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NotesScreen(
          notesRepository: repository,
          currentUserId: 'me',
          threadId: 'chat-1',
          onSharedNoteCreated: (noteId) async => sharedNoteIds.add(noteId),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Text Note'));
    await tester.pumpAndSettle();

    expect(repository.private, isEmpty);
    expect(repository.shared, hasLength(1));
    expect(repository.shared.single.threadId, 'chat-1');
    expect(sharedNoteIds, [repository.shared.single.id]);
    expect(find.byType(NoteEditorScreen), findsOneWidget);
  });

  testWidgets('shared note shows an active editor and releases its lease', (
    tester,
  ) async {
    final note = _note('Shared', threadId: 'chat-1');
    repository.shared.add(note);
    await repository.setThreadNoteEditing(
      threadId: 'chat-1',
      noteId: note.id,
      uid: 'other-user',
      isEditing: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorScreen(
          note: note,
          notesRepository: repository,
          currentUserId: 'me',
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Someone else is editing this note'), findsOneWidget);
    expect(repository.editors['chat-1/Shared']?.keys, contains('me'));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(repository.editors['chat-1/Shared']?.keys, isNot(contains('me')));
  });

  testWidgets('private create starts empty and saves before opening editor', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotesScreen(notesRepository: repository, currentUserId: 'me'),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Checklist'));
    await tester.pumpAndSettle();

    expect(repository.private, hasLength(1));
    expect(repository.private.single.title, isEmpty);
    expect(repository.private.single.items, isEmpty);
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect(find.text('First item'), findsNothing);
    expect(find.text('List item'), findsNothing);

    await tester.tap(find.text('Add item'));
    await tester.pump();
    expect(find.text('List item'), findsOneWidget);

    await tester.enterText(_emptyChecklistFields(), 'First real item');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump(const Duration(milliseconds: 650));
    await tester.pumpAndSettle();
    expect(repository.private.single.items.single.text, 'First real item');
    expect(_emptyChecklistFields(), findsOneWidget);

    await tester.tap(find.widgetWithText(TextField, 'First real item'));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    expect(
      tester.widget<TextField>(_emptyChecklistFields()).focusNode!.hasFocus,
      isTrue,
    );

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();
    expect(find.byType(NoteEditorScreen), findsNothing);
    expect(find.text('First real item'), findsOneWidget);
  });

  testWidgets('private text note edits persist across reopening', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NotesScreen(notesRepository: repository, currentUserId: 'me'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Text Note'));
    await tester.pumpAndSettle();

    expect(repository.private.single.title, isEmpty);
    expect(repository.private.single.content, isEmpty);
    await tester.enterText(find.widgetWithText(TextField, 'Title'), 'My note');
    await tester.enterText(
      find.widgetWithText(TextField, 'Type your note here…'),
      'Saved content',
    );
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(repository.private.single.title, 'My note');
    expect(repository.private.single.content, 'Saved content');
    expect(find.byType(NoteEditorScreen), findsNothing);
    await tester.tap(find.text('My note'));
    await tester.pumpAndSettle();
    expect(find.text('Saved content'), findsOneWidget);
  });

  testWidgets('failed save keeps editor open with an error', (tester) async {
    repository.failSave = true;
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorScreen(
          note: _note('Draft'),
          notesRepository: repository,
          currentUserId: 'me',
        ),
      ),
    );
    await tester.tap(find.byTooltip('Save'));
    await tester.pump();
    expect(find.byType(NoteEditorScreen), findsOneWidget);
    expect(find.textContaining('Could not save note:'), findsOneWidget);
  });

  testWidgets('failed private creation does not open the editor', (
    tester,
  ) async {
    repository.failSave = true;
    await tester.pumpWidget(
      MaterialApp(
        home: NotesScreen(notesRepository: repository, currentUserId: 'me'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New Text Note'));
    await tester.pumpAndSettle();

    expect(repository.private, isEmpty);
    expect(find.byType(NoteEditorScreen), findsNothing);
    expect(find.textContaining('Could not create note:'), findsOneWidget);
  });

  testWidgets('overlapping autosaves persist the latest edit last', (
    tester,
  ) async {
    final gate = Completer<void>();
    repository.nextPrivateSaveGate = gate;
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorScreen(
          note: _note('Original'),
          notesRepository: repository,
          currentUserId: 'me',
        ),
      ),
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'First edit',
    );
    await tester.pump(const Duration(milliseconds: 650));
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Latest edit',
    );
    await tester.pump(const Duration(milliseconds: 650));
    gate.complete();
    await tester.pumpAndSettle();

    expect(repository.private.single.title, 'Latest edit');
  });

  testWidgets('Enter inserts an item below and Backspace removes blank above', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorScreen(
          note: _checklist('Keyboard'),
          notesRepository: repository,
          currentUserId: 'me',
        ),
      ),
    );

    await tester.tap(find.widgetWithText(TextField, 'First'));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pumpAndSettle();
    expect(_emptyChecklistFields(), findsOneWidget);

    final blank = _emptyChecklistFields();
    await tester.tap(blank);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(_emptyChecklistFields(), findsNothing);
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, 'First'))
          .focusNode!
          .hasFocus,
      isTrue,
    );
  });

  testWidgets('pinning a note syncs and sorts it before unpinned notes', (
    tester,
  ) async {
    repository.shared.addAll([
      _note('Unpinned', threadId: 'chat-1', updatedAt: DateTime.utc(2025)),
      _note('To pin', threadId: 'chat-1', updatedAt: DateTime.utc(2024)),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: NotesScreen(
          notesRepository: repository,
          currentUserId: 'me',
          threadId: 'chat-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    expect(repository.shared.last.isPinned, isTrue);
    expect(
      tester.getTopLeft(find.text('To pin')).dx,
      lessThan(tester.getTopLeft(find.text('Unpinned')).dx),
    );
  });

  testWidgets('shared delete menu is only shown to its creator', (
    tester,
  ) async {
    repository.shared.add(_note('Owned by another', threadId: 'chat-1'));
    await tester.pumpWidget(
      MaterialApp(
        home: NotesScreen(
          notesRepository: repository,
          currentUserId: 'another-user',
          threadId: 'chat-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text('Delete'), findsNothing);
    expect(find.text('Pin'), findsOneWidget);
  });

  testWidgets('creator can delete a shared checklist', (tester) async {
    repository.shared.add(
      _note('Owned checklist', threadId: 'chat-1', type: NoteType.checklist),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NotesScreen(
          notesRepository: repository,
          currentUserId: 'me',
          threadId: 'chat-1',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.shared, isEmpty);
  });

  testWidgets('checklist has a visible action to add an item', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorScreen(
          note: _checklist('Add item'),
          notesRepository: repository,
          currentUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addItemButton = find.widgetWithText(InkWell, 'Add item');
    expect(addItemButton, findsOneWidget);
    await tester.tap(addItemButton);
    await tester.pump();

    final emptyField = tester.widget<TextField>(_emptyChecklistFields());
    expect(emptyField.focusNode?.hasFocus, isTrue);
  });

  testWidgets('reordering checklist items saves the new order', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorScreen(
          note: _checklist('Reorder'),
          notesRepository: repository,
          currentUserId: 'me',
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.getCenter(
      find.byKey(const ValueKey('drag-handle-Reorder-1')),
    );
    await tester.timedDragFrom(
      first,
      const Offset(0, 120),
      const Duration(milliseconds: 300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(repository.private.single.items.map((item) => item.text).toList(), [
      'Second',
      'First',
    ]);
  });

  testWidgets('line and item presence clues highlight active collaborator position', (
    tester,
  ) async {
    final checklist = AppNote(
      id: 'shared-cl',
      threadId: 'chat-1',
      creatorId: 'me',
      type: NoteType.checklist,
      title: 'Groceries',
      items: const [ChecklistItem(id: 'item-1', text: 'Milk')],
      createdAt: DateTime.utc(2024, 1, 1),
      updatedAt: DateTime.utc(2024, 1, 2),
    );
    repository.shared.add(checklist);
    await repository.setThreadNoteEditing(
      threadId: 'chat-1',
      noteId: 'shared-cl',
      uid: 'other-user',
      isEditing: true,
      editingTarget: 'item',
      editingItemId: 'item-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorScreen(
          note: checklist,
          notesRepository: repository,
          currentUserId: 'me',
        ),
      ),
    );
    await tester.pump();

    expect(
      find.text('Someone else is editing this note • "Milk"'),
      findsOneWidget,
    );
    expect(find.text('Editing'), findsOneWidget);
  });

  testWidgets('deleting an actively edited note warns the deleter first', (
    tester,
  ) async {
    final note = _note('Active', threadId: 'chat-1');
    repository.shared.add(note);
    await repository.setThreadNoteEditing(
      threadId: 'chat-1',
      noteId: note.id,
      uid: 'other-user',
      isEditing: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NotesScreen(
          notesRepository: repository,
          currentUserId: 'me',
          threadId: 'chat-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Note is being edited'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.shared, hasLength(1));

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repository.shared, isEmpty);
  });

  testWidgets('editor shows recovery banner when note is deleted remotely', (
    tester,
  ) async {
    final note = _note('Shared', threadId: 'chat-1');
    repository.shared.add(note);

    await tester.pumpWidget(
      MaterialApp(
        home: NoteEditorScreen(
          note: note,
          notesRepository: repository,
          currentUserId: 'me',
        ),
      ),
    );
    await tester.pump();

    await repository.deleteThreadNote(threadId: 'chat-1', noteId: note.id);
    await tester.pump();

    expect(
      find.textContaining('This note was deleted by the other participant'),
      findsOneWidget,
    );
    expect(find.text('Save copy'), findsOneWidget);
  });

  testWidgets('SharedNoteBubble updates live when remote note changes', (
    tester,
  ) async {
    final note = _note('Initial title', threadId: 'chat-1');
    repository.shared.add(note);
    final message = ChatMessage(
      messageId: 'm1',
      threadId: 'chat-1',
      senderId: 'other',
      encryptedText: '',
      localDecryptedText: 'Shared a note',
      sentAt: DateTime.utc(2024, 1, 2),
      deletedFor: const [],
      mediaType: MessageType.sharedNote,
      sharedNoteId: note.id,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SharedNoteBubble(
            message: message,
            isMine: false,
            currentUserId: 'me',
            notesRepository: repository,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Initial title'), findsOneWidget);

    await repository.saveThreadNote(
      note.copyWith(title: 'Updated live title', updatedAt: DateTime.utc(2024, 1, 3)),
    );
    await tester.pump();
    expect(find.text('Updated live title'), findsOneWidget);
  });
}
