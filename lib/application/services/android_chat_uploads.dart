import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/message_metadata.dart';
import '../../presentation/state/chat/media_send_status.dart';

/// The native journal is authoritative; polling is a view, not another queue.
class AndroidChatUploads {
  AndroidChatUploads({
    MethodChannel channel = const MethodChannel('photo_vault/chat_uploads'),
  }) : _channel = channel;

  final MethodChannel _channel;
  final _changes = StreamController<List<AndroidUploadJob>>.broadcast();
  Stream<List<AndroidUploadJob>> get changes => _changes.stream;
  List<AndroidUploadJob> _jobs = const [];
  List<AndroidUploadJob> get jobs => _jobs;
  Timer? _timer;
  bool _refreshing = false;
  String? _uid;
  String? _lastReadFailure;

  void start(String uid) {
    if (_uid == uid && _timer != null) return;
    stop();
    _uid = uid;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
    unawaited(
      _command('wake').catchError((Object error, StackTrace stack) {
        if (_uid == uid && !_changes.isClosed) _changes.addError(error, stack);
      }),
    );
    _refresh();
  }

  void stop() {
    _uid = null;
    _timer?.cancel();
    _timer = null;
    _jobs = const [];
    _lastReadFailure = null;
  }

  Future<void> _refresh() async {
    if (_refreshing || _uid == null) return;
    _refreshing = true;
    final uid = _uid;
    try {
      final list = await _channel.invokeListMethod<dynamic>('list');
      if (uid != _uid || _changes.isClosed) return;
      _jobs = (list ?? [])
          .map((value) {
            if (value is! Map) {
              throw const FormatException('Invalid upload journal response.');
            }
            return AndroidUploadJob.fromMap(Map<Object?, Object?>.from(value));
          })
          .where((job) => job.message.senderId == uid)
          .toList();
      _changes.add(_jobs);
      _lastReadFailure = null;
    } on PlatformException catch (error, stack) {
      _readError(uid, error, stack);
    } on MissingPluginException catch (error, stack) {
      _readError(uid, error, stack);
    } on FormatException catch (error, stack) {
      _readError(uid, error, stack);
    } finally {
      _refreshing = false;
    }
  }

  void _readError(String? uid, Object error, StackTrace stack) {
    final signature = error.toString();
    if (uid == _uid && !_changes.isClosed && _lastReadFailure != signature) {
      _lastReadFailure = signature;
      _changes.addError(error, stack);
    }
  }

  Future<void> enqueue({
    required ChatMessage message,
    required String recipientUid,
    required Uint8List ciphertext,
    Uint8List? thumbnail,
  }) async {
    await _channel.invokeMethod<void>('enqueue', {
      'messageId': message.messageId,
      'threadId': message.threadId,
      'senderId': message.senderId,
      'recipientUid': recipientUid,
      'encryptedText': message.encryptedText,
      'mediaType': message.mediaType!.name,
      'mediaMeta': message.mediaMeta?.toFirestore() ?? <String, dynamic>{},
      'sentAt': message.sentAt.toUtc().millisecondsSinceEpoch,
      'isForwarded': message.isForwarded,
      'bytes': ciphertext,
      'thumbnail': thumbnail,
    });
    await _refresh();
  }

  Future<void> pause(String id) => _command('pause', id);

  /// Handoff of legacy outbox entries whose encrypted object is already remote.
  /// No second upload is performed, and acceptance precedes old-queue removal.
  Future<void> recoverUploaded(ChatMessage message, String recipientUid) async {
    await _channel.invokeMethod<void>('recoverUploaded', {
      'messageId': message.messageId,
      'threadId': message.threadId,
      'senderId': message.senderId,
      'recipientUid': recipientUid,
      'encryptedText': message.encryptedText,
      'mediaRef': message.mediaRef,
      'mediaType': message.mediaType!.name,
      'mediaMeta': message.mediaMeta?.toFirestore() ?? <String, dynamic>{},
      'sentAt': message.sentAt.toUtc().millisecondsSinceEpoch,
    });
    await _refresh();
  }

  Future<void> resume(String id) => _command('resume', id);
  Future<void> cancel(String id) async {
    final job = await _channel.invokeMapMethod<Object?, Object?>('cancel', {
      'messageId': id,
    });
    if (job?['state'] != 'cancelled') {
      throw StateError(
        'Delivery is already committing. Delete the message after it is sent.',
      );
    }
    await _refresh();
  }

  Future<void> retry(String id) => _command('retry', id);
  Future<void> acknowledge(String id) => _command('acknowledge', id);
  Future<void> _command(String command, [String? id]) async {
    await _channel.invokeMethod<dynamic>(
      command,
      id == null ? null : {'messageId': id},
    );
    await _refresh();
  }

  void dispose() {
    stop();
    unawaited(_changes.close());
  }
}

class AndroidUploadJob {
  AndroidUploadJob({required this.message, required this.status, this.error});
  final ChatMessage message;
  final MediaSendStatus status;
  final String? error;

  factory AndroidUploadJob.fromMap(Map<Object?, Object?> map) {
    String text(String key) {
      final value = map[key];
      if (value is! String || value.isEmpty) {
        throw FormatException('Invalid upload field: $key.');
      }
      return value;
    }

    int number(String key) {
      final value = map[key];
      if (value is! num ||
          !value.isFinite ||
          value < 0 ||
          value.toInt() != value) {
        throw FormatException('Invalid upload field: $key.');
      }
      return value.toInt();
    }

    final lifecycle = MediaUploadLifecycle.values
        .where((value) => value.name == text('state'))
        .firstOrNull;
    final mediaType = MessageType.values
        .where((value) => value.name == text('mediaType'))
        .firstOrNull;
    if (lifecycle == null || mediaType == null) {
      throw const FormatException('Unsupported upload state or media type.');
    }
    final processed = number('processedBytes');
    final total = number('totalBytes');
    final sentAt = number('sentAt');
    if (sentAt > 8640000000000000) {
      throw const FormatException('Invalid upload timestamp.');
    }
    for (final key in ['mediaRef', 'error']) {
      if (map[key] != null && map[key] is! String) {
        throw FormatException('Invalid upload field: $key.');
      }
    }
    if (map['isForwarded'] != null && map['isForwarded'] is! bool) {
      throw const FormatException('Invalid forwarded upload flag.');
    }
    final meta = map['mediaMeta'];
    if (meta != null && meta is! Map) {
      throw const FormatException('Invalid upload metadata.');
    }
    if (meta is Map) {
      if (meta.keys.any((key) => key is! String)) {
        throw const FormatException('Invalid upload metadata keys.');
      }
      for (final key in ['width', 'height', 'sizeBytes']) {
        final value = meta[key];
        if (value != null && (value is! num || !value.isFinite || value < 0)) {
          throw FormatException('Invalid upload media field: $key.');
        }
      }
      if (meta['thumbRef'] != null && meta['thumbRef'] is! String) {
        throw const FormatException('Invalid upload thumbnail reference.');
      }
    }
    return AndroidUploadJob(
      message: ChatMessage(
        messageId: text('messageId'),
        threadId: text('threadId'),
        senderId: text('senderId'),
        encryptedText: text('encryptedText'),
        sentAt: DateTime.fromMillisecondsSinceEpoch(sentAt, isUtc: true),
        deletedFor: const [],
        mediaType: mediaType,
        isForwarded: map['isForwarded'] == true,
        mediaRef: map['mediaRef'] as String?,
        mediaMeta: meta is Map
            ? MediaMeta.fromFirestore(Map<String, dynamic>.from(meta))
            : null,
        status: lifecycle == MediaUploadLifecycle.completed
            ? MessageStatus.sent
            : lifecycle == MediaUploadLifecycle.failed
            ? MessageStatus.failed
            : MessageStatus.sending,
      ),
      status: MediaSendStatus(
        phase: MediaSendPhase.uploading,
        lifecycle: lifecycle,
        processedBytes: processed,
        totalBytes: total,
        progress: total == 0 ? 0 : (processed / total).clamp(0, 1),
      ),
      error: map['error'] as String?,
    );
  }
}
