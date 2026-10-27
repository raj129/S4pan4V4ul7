import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../application/crypto/chat_crypto_service.dart';
import '../../domain/entities/app_note.dart';
import '../../domain/repositories/notes_repository.dart';
import 'package:photo_vault/features/vault/data/repositories/storage_string_kv.dart';

/// Combined implementation of [NotesRepository]:
/// - Shared notes are synced via Firestore at `threads/{threadId}/notes/{noteId}` with E2EE.
/// - Private notes are stored encrypted locally in secure KV / vault storage.
class AppNotesRepository implements NotesRepository {
  AppNotesRepository({
    FirebaseFirestore? firestore,
    required ChatCryptoService cryptoService,
    required StorageStringKv secureKv,
  }) : _firestore = firestore,
       _crypto = cryptoService,
       _kv = secureKv;

  final FirebaseFirestore? _firestore;
  FirebaseFirestore get _db =>
      _firestore ??
      FirebaseFirestore.instanceFor(
        app: Firebase.app(),
        databaseId: 'default1',
      );
  final ChatCryptoService _crypto;
  final StorageStringKv _kv;

  static const _privateNotesIndexKey = 'vault_private_notes_index';
  static String _privateNoteKey(String id) => 'vault_private_note_$id';

  final _privateNotesController = StreamController<List<AppNote>>.broadcast();

  CollectionReference<Map<String, dynamic>> _notesRef(String threadId) =>
      _db.collection('threads').doc(threadId).collection('notes');

  DocumentReference<Map<String, dynamic>> _noteDoc(
    String threadId,
    String noteId,
  ) => _notesRef(threadId).doc(noteId);

  // ── Thread Notes (E2EE Firestore) ──────────────────────────────────────────

  @override
  Stream<List<AppNote>> watchThreadNotes(String threadId) {
    return _notesRef(threadId)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .asyncMap((snapshot) async {
          final notes = <AppNote>[];
          for (final doc in snapshot.docs) {
            final data = doc.data();
            final encryptedPayload = data['encryptedPayload'] as String?;
            if (encryptedPayload == null) continue;
            try {
              final decryptedJson = await _crypto.decryptMessage(
                threadId: threadId,
                encryptedB64: encryptedPayload,
              );
              final note = AppNote.deserialize(decryptedJson);
              notes.add(note);
            } catch (_) {
              // Skip corrupt or unreadable note payload
            }
          }
          return notes;
        });
  }

  @override
  Future<AppNote?> getThreadNote({
    required String threadId,
    required String noteId,
  }) async {
    final doc = await _noteDoc(threadId, noteId).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    final encryptedPayload = data['encryptedPayload'] as String?;
    if (encryptedPayload == null) return null;
    try {
      final decryptedJson = await _crypto.decryptMessage(
        threadId: threadId,
        encryptedB64: encryptedPayload,
      );
      return AppNote.deserialize(decryptedJson);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveThreadNote(AppNote note) async {
    final threadId = note.threadId;
    if (threadId == null || threadId.isEmpty) {
      throw ArgumentError('Shared note must have non-empty threadId');
    }
    final noteJson = note.serialize();
    final encryptedPayload = await _crypto.encryptMessage(
      threadId: threadId,
      plaintext: noteJson,
    );

    await _noteDoc(threadId, note.id).set({
      'id': note.id,
      'threadId': threadId,
      'creatorId': note.creatorId,
      'type': note.type.name,
      'isChecklist': note.isChecklist,
      'updatedAt': note.updatedAt.toUtc().millisecondsSinceEpoch,
      'lastEditedBy': note.lastEditedBy ?? note.creatorId,
      'encryptedPayload': encryptedPayload,
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteThreadNote({
    required String threadId,
    required String noteId,
  }) async {
    await _noteDoc(threadId, noteId).delete();
  }

  // ── Private Notes (Local Secure Vault Storage) ──────────────────────────────

  Future<List<String>> _getPrivateIds() async {
    final raw = await _kv.read(_privateNotesIndexKey);
    if (raw == null || raw.isEmpty) return [];
    return List<String>.from(jsonDecode(raw) as List);
  }

  Future<void> _setPrivateIds(List<String> ids) async {
    await _kv.write(_privateNotesIndexKey, jsonEncode(ids));
  }

  Future<List<AppNote>> _loadAllPrivateNotes() async {
    final ids = await _getPrivateIds();
    final list = <AppNote>[];
    for (final id in ids) {
      final raw = await _kv.read(_privateNoteKey(id));
      if (raw == null) throw StateError('Private note $id is missing');
      list.add(AppNote.deserialize(raw));
    }
    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  Future<void> _emitPrivateNotes() async {
    if (_privateNotesController.isClosed) return;
    final notes = await _loadAllPrivateNotes();
    _privateNotesController.add(notes);
  }

  @override
  Stream<List<AppNote>> watchPrivateNotes() {
    return Stream.multi((controller) {
      var active = true;
      var updated = false;
      final subscription = _privateNotesController.stream.listen((notes) {
        updated = true;
        controller.add(notes);
      }, onError: controller.addError);
      _loadAllPrivateNotes().then(
        (notes) {
          if (active && !updated) controller.add(notes);
        },
        onError: (Object error, StackTrace stack) {
          if (active) controller.addError(error, stack);
        },
      );
      controller.onCancel = () {
        active = false;
        return subscription.cancel();
      };
    });
  }

  @override
  Future<void> savePrivateNote(AppNote note) async {
    final ids = await _getPrivateIds();
    await _kv.write(_privateNoteKey(note.id), note.serialize());
    if (!ids.contains(note.id)) {
      ids.add(note.id);
      await _setPrivateIds(ids);
    }
    await _emitPrivateNotes();
  }

  @override
  Future<void> deletePrivateNote(String noteId) async {
    final ids = await _getPrivateIds();
    ids.remove(noteId);
    await _setPrivateIds(ids);
    await _kv.delete(_privateNoteKey(noteId));
    await _emitPrivateNotes();
  }
}
