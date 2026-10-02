import 'dart:async';

import '../../../domain/repositories/message_repository.dart';
import 'media_send_status.dart';

/// Tracks attachments that are being prepared or uploaded right now.
///
/// This is deliberately separate from any cubit: leaving a chat, re-opening it
/// or closing a route-scoped cubit must not lose the progress of a send that
/// is still running, nor the ability to cancel it.
class ActiveUploadRegistry {
  ActiveUploadRegistry();

  /// One registry for the whole app, so every cubit sees the same sends.
  static final ActiveUploadRegistry shared = ActiveUploadRegistry();

  final Map<String, MediaSendStatus> _statuses = {};
  final Map<String, UploadCancelToken> _tokens = {};
  final Set<String> _delivering = {};
  final StreamController<Map<String, MediaSendStatus>> _changes =
      StreamController<Map<String, MediaSendStatus>>.broadcast(sync: true);

  /// Current progress of every send that is reporting it.
  Map<String, MediaSendStatus> get statuses => Map.unmodifiable(_statuses);

  /// Emits a fresh snapshot whenever any send's progress changes.
  Stream<Map<String, MediaSendStatus>> get changes => _changes.stream;

  MediaSendStatus? statusOf(String messageId) => _statuses[messageId];

  /// Publishes (or clears, when [status] is null) the progress of a send.
  void setStatus(String messageId, MediaSendStatus? status) {
    if (status == null) {
      if (_statuses.remove(messageId) == null) return;
    } else {
      if (_statuses[messageId] == status) return;
      _statuses[messageId] = status;
    }
    if (!_changes.isClosed) _changes.add(statuses);
  }

  /// Advances the bar within one phase, never backwards.
  void advance(String messageId, MediaSendPhase phase, double progress) {
    final existing = _statuses[messageId];
    // A late callback from an earlier phase must not rewind the ring.
    if (existing != null && progress < existing.progress) return;
    setStatus(messageId, MediaSendStatus(phase: phase, progress: progress));
  }

  /// The cancel token for [messageId], created on first use.
  UploadCancelToken register(String messageId) =>
      _tokens.putIfAbsent(messageId, UploadCancelToken.new);

  UploadCancelToken? tokenOf(String messageId) => _tokens[messageId];

  /// Forgets the send's token and progress once it has finished.
  void release(String messageId) {
    _tokens.remove(messageId);
    setStatus(messageId, null);
  }

  /// Claims the delivery of [messageId]; false if another call already has it.
  bool tryBeginDelivery(String messageId) => _delivering.add(messageId);

  void endDelivery(String messageId) => _delivering.remove(messageId);

  /// Whether a live sender (preparing, encrypting or uploading) owns the
  /// message, so nobody else may deliver or fail it.
  bool isActive(String messageId) =>
      _tokens.containsKey(messageId) || _delivering.contains(messageId);

  Set<String> get activeIds => {..._tokens.keys, ..._delivering};
}
