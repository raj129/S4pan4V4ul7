import '../entities/app_note.dart';

abstract class NotesRepository {
  /// Stream notes belonging to a specific chat thread, ordered by updatedAt descending.
  Stream<List<AppNote>> watchThreadNotes(String threadId);

  /// Load a single note by id in a thread.
  Future<AppNote?> getThreadNote({
    required String threadId,
    required String noteId,
  });

  /// Create or update a shared note in a thread with E2EE encryption.
  Future<void> saveThreadNote(AppNote note);

  /// Observe participant UIDs with a non-expired editing lease for a note.
  Stream<List<String>> watchThreadNoteEditors({
    required String threadId,
    required String noteId,
  });

  /// Renew or release the caller's editing lease for a shared note.
  Future<void> setThreadNoteEditing({
    required String threadId,
    required String noteId,
    required String uid,
    required bool isEditing,
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
