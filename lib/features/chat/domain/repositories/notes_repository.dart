import '../entities/app_note.dart';

abstract class NotesRepository {
  /// Stream notes belonging to a specific chat thread, ordered by updatedAt descending.
  Stream<List<AppNote>> watchThreadNotes(String threadId);

  /// Stream a single shared note in a thread (emits null when deleted/missing).
  Stream<AppNote?> watchThreadNote({
    required String threadId,
    required String noteId,
  });

  /// Load a single note by id in a thread.
  Future<AppNote?> getThreadNote({
    required String threadId,
    required String noteId,
  });

  /// Create or update a shared note in a thread with E2EE encryption.
  /// When [baseNote] is provided and the note already exists remotely,
  /// performs a transactional 3-way merge and returns the saved note.
  Future<AppNote> saveThreadNote(AppNote note, {AppNote? baseNote});

  /// Observe participant UIDs with a non-expired editing lease for a note.
  Stream<List<String>> watchThreadNoteEditors({
    required String threadId,
    required String noteId,
  });

  /// Observe detailed editing presence (including line/item/cursor) for a note.
  Stream<List<NoteEditorPresence>> watchThreadNoteEditorPresences({
    required String threadId,
    required String noteId,
  });

  /// Renew or release the caller's editing lease for a shared note.
  Future<void> setThreadNoteEditing({
    required String threadId,
    required String noteId,
    required String uid,
    required bool isEditing,
    String? editingTarget,
    String? editingItemId,
    int? editingLine,
    int? cursorOffset,
  });

  /// Delete a shared note from a thread.
  Future<void> deleteThreadNote({
    required String threadId,
    required String noteId,
  });

  /// Stream all private notes saved in the local vault.
  Stream<List<AppNote>> watchPrivateNotes();

  /// Save or update a private note locally in the vault.
  Future<void> savePrivateNote(AppNote note);

  /// Delete a private note from the vault.
  Future<void> deletePrivateNote(String noteId);
}
