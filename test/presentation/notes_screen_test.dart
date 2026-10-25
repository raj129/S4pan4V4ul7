import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:photo_vault/core/widgets/app_navigation_drawer.dart';
import 'package:photo_vault/features/chat/domain/entities/app_note.dart';
import 'package:photo_vault/features/chat/domain/repositories/notes_repository.dart';
import 'package:photo_vault/features/chat/presentation/screens/note_editor_screen.dart';
import 'package:photo_vault/features/chat/presentation/screens/notes_screen.dart';

class _NotesRepository implements NotesRepository {
  final private = <AppNote>[];
  final shared = <AppNote>[];
  final privateUpdates = StreamController<List<AppNote>>.broadcast();
  final sharedUpdates = StreamController<List<AppNote>>.broadcast();
  bool failSave = false;
  String? watchedThread;
  Completer<void>? nextPrivateSaveGate;

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
  Future<void> saveThreadNote(AppNote note) async {
    if (failSave) throw StateError('network unavailable');
    shared.removeWhere((item) => item.id == note.id);
    shared.add(note);
    sharedUpdates.add(List.of(shared));
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
    expect(navigationPathForDestination(5), '/settings');
    expect(navigationPathForDestination(6), isNull);
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
      expect(find.text('Create'), findsNothing);

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
    final gesture = await tester.startGesture(first);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(0, 100));
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(repository.private.single.items.map((item) => item.text).toList(), [
      'Second',
      'First',
    ]);
  });
}
