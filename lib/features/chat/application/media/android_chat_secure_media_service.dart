import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:photo_vault/core/app/android_chat_viewer_guard.dart';
import 'chat_media_timings.dart';

/// Android-only acquisition/viewing. No attachment is exported to a file.
/// Managed runtimes cannot guarantee erasure of all copies of a byte buffer.
class AndroidChatSecureMediaService {
  const AndroidChatSecureMediaService({
    MethodChannel channel = const MethodChannel(
      'photo_vault/chat_secure_media',
    ),
  }) : _channel = channel;

  static const maxBytes = 64 * 1024 * 1024 - 1024;
  static const maxRecordingDuration = Duration(minutes: 5);
  final MethodChannel _channel;

  Future<List<SecureMediaAttachment>> pickAttachments({
    List<String> mimeTypes = const ['*/*'],
  }) async {
    final result = await _channel.invokeListMethod<dynamic>('pickAttachments', {
      'mimeTypes': mimeTypes,
    });
    return (result ?? []).map((item) {
      return SecureMediaAttachment.fromMap(Map<Object?, Object?>.from(item));
    }).toList();
  }

  Future<SecureMediaAttachment> readContentUri(String uri) async {
    if (!uri.startsWith('content://')) {
      throw ArgumentError('Only Android content URIs are accepted.');
    }
    return _attachment('readContentUri', {'uri': uri});
  }

  /// Camera2 captures a JPEG directly to memory; no camera intent/file staging.
  Future<SecureMediaAttachment?> capturePhoto() async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      'capturePhoto',
    );
    return result == null ? null : SecureMediaAttachment.fromMap(result);
  }

  Future<void> startRecording() => _channel.invokeMethod('startRecording');
  Future<void> pauseRecording() => _channel.invokeMethod('pauseRecording');
  Future<void> resumeRecording() => _channel.invokeMethod('resumeRecording');
  Future<String> recordingStatus() async {
    final status = await _channel.invokeMethod<String>('recordingStatus');
    if (!const {
      'recording',
      'paused',
      'completed',
      'failed',
      'interrupted',
    }.contains(status)) {
      throw StateError('Invalid native recording state.');
    }
    return status!;
  }

  /// Returns a bounded WAV in memory for thread encryption. The native spool
  /// is authenticated ciphertext and is removed on stop/cancel/interruption.
  Future<SecureMediaAttachment> stopRecording() =>
      _attachment('stopRecording', null);

  Future<void> cancelRecording() => _channel.invokeMethod('cancelRecording');

  Future<void> showVideo(Uint8List bytes) => _show('showVideo', bytes);
  Future<void> showAudio(Uint8List bytes) => _show('showAudio', bytes);

  /// API 26+ uses a memory-backed proxy descriptor; older Android returns
  /// `unsupported` rather than staging a plaintext PDF.
  Future<void> showPdf(Uint8List bytes) => _show('showPdf', bytes);

  /// Call on account change/sign-out and screen disposal. Releases players,
  /// camera, PDFs, and recording spool, and zeroes owned native buffers.
  Future<void> close() => _channel.invokeMethod('close');

  Future<void> _show(String method, Uint8List bytes) {
    _validate(bytes);
    return AndroidChatViewerGuard.run(() {
      final dispatch = Stopwatch()..start();
      final result = _channel.invokeMethod<void>(method, {
        'bytes': bytes,
        if (method == 'showVideo' && !kReleaseMode) 'measureStartup': true,
      });
      ChatMediaTimings.record('native-dispatch', dispatch, bytes: bytes.length);
      return result;
    });
  }

  Future<SecureMediaAttachment> _attachment(
    String method,
    Map<String, Object?>? arguments,
  ) async {
    final result = await _channel.invokeMapMethod<Object?, Object?>(
      method,
      arguments,
    );
    if (result == null) throw StateError('Attachment acquisition cancelled.');
    return SecureMediaAttachment.fromMap(result);
  }

  static void _validate(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw ArgumentError('Attachment must be nonempty and below 64 MB.');
    }
  }
}

class SecureMediaAttachment {
  const SecureMediaAttachment({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    this.sourceUri,
    this.sourceFlags = 0,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final String? sourceUri;
  final int sourceFlags;

  factory SecureMediaAttachment.fromMap(Map<Object?, Object?> map) {
    final bytes = map['bytes'];
    if (bytes is! Uint8List) throw StateError('Invalid native attachment.');
    AndroidChatSecureMediaService._validate(bytes);
    return SecureMediaAttachment(
      bytes: Uint8List.fromList(bytes),
      fileName: map['fileName'] as String? ?? 'attachment',
      mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
      sourceUri: map['sourceUri'] as String?,
      sourceFlags: map['sourceFlags'] as int? ?? 0,
    );
  }
}
