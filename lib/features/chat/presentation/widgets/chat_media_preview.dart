import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';

import '../../application/media/chat_media_loader.dart';
import '../../application/media/android_chat_local_media.dart';
import '../../application/media/android_chat_secure_media_service.dart';
import '../../domain/entities/chat_message.dart';
import '../../application/media/media_send_status.dart';
import '../screens/chat_image_viewer_screen.dart';
import 'attachment_download_progress.dart';
import 'attachment_upload_progress.dart';

export '../../application/media/chat_media_loader.dart';

String? chatMediaFailureMessage(Object? error) => switch (error) {
  ChatLocalMediaException(:final message) => message,
  PlatformException(:final message) => message,
  _ => null,
};

bool chatMediaRequiresAction(Object? error) {
  final code = switch (error) {
    ChatLocalMediaException(:final code) => code,
    PlatformException(:final code) => code,
    _ => null,
  };
  return const {
    'source_unavailable',
    'source_permission_denied',
    'source_changed',
    'source_corrupt',
    'local_media_moved',
    'moved',
    'storage_full',
    'local_media_storage_full',
    'local_media_unauthorized',
    'disk_full',
    'identity_missing',
    'account_changed',
  }.contains(code);
}

/// Renders decrypted image/video attachments inside a bubble.
class ChatMediaPreview extends StatefulWidget {
  const ChatMediaPreview({
    super.key,
    required this.message,
    required this.loader,
    this.onTap,
    this.sendStatus,
    this.onCancel,
  });

  final ChatMessage message;
  final ChatMediaLoader loader;
  final VoidCallback? onTap;

  /// Progress of this attachment while it is being sent, null once it is sent.
  final MediaSendStatus? sendStatus;

  /// Stops the send while [sendStatus] is showing.
  final VoidCallback? onCancel;

  @override
  State<ChatMediaPreview> createState() => _ChatMediaPreviewState();
}

class _ChatMediaPreviewState extends State<ChatMediaPreview> {
  Uint8List? _bytes;
  ResizeImage? _previewImage;
  bool _loading = false;
  bool _failed = false;
  Object? _error;
  int _generation = 0;
  int _attempt = 0;

  static const _maxAutoRetries = 3;

  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    widget.loader.addListener(_onLoaderChanged);
    _start();
  }

  @override
  void didUpdateWidget(ChatMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) {
      oldWidget.loader.removeListener(_onLoaderChanged);
      widget.loader.addListener(_onLoaderChanged);
    }
    if (oldWidget.message.previewRef != widget.message.previewRef ||
        oldWidget.message.threadId != widget.message.threadId ||
        oldWidget.message.messageId != widget.message.messageId ||
        oldWidget.message.senderId != widget.message.senderId ||
        oldWidget.loader != widget.loader) {
      _attempt = 0;
      _retryTimer?.cancel();
      _releaseBytes();
      _start();
    } else if (oldWidget.sendStatus != null && widget.sendStatus == null) {
      _start();
    }
  }

  void _onLoaderChanged() {
    if (!mounted || _bytes != null) return;
    final ref = widget.message.previewRef;
    final bytes = ref == null ? null : widget.loader.cached(ref);
    if (bytes == null) return;
    _retryTimer?.cancel();
    setState(() {
      _bytes = bytes;
      _loading = false;
      _failed = false;
      _error = null;
    });
  }

  @override
  void dispose() {
    widget.loader.removeListener(_onLoaderChanged);
    _retryTimer?.cancel();
    _generation++;
    _releaseBytes();
    super.dispose();
  }

  void _releaseBytes() {
    final bytes = _bytes;
    _bytes = null;
    if (bytes == null) return;
    final previewImage = _previewImage;
    _previewImage = null;
    if (previewImage != null) unawaited(previewImage.evict());
    unawaited(MemoryImage(bytes).evict());
    bytes.fillRange(0, bytes.length, 0);
  }

  /// A failed load would otherwise stay broken until the chat is reopened.
  void _scheduleRetry() {
    if (chatMediaRequiresAction(_error)) return;
    if (_attempt >= _maxAutoRetries || _retryTimer?.isActive == true) return;
    _attempt++;
    _retryTimer = Timer(Duration(seconds: 2 * _attempt), _retryNow);
  }

  void _retryNow() {
    if (!mounted) return;
    _retryTimer?.cancel();
    setState(() {
      if (_bytes?.isEmpty == true) _releaseBytes();
      _start();
    });
  }

  /// While uploading there is no object to fetch; show a placeholder instead.
  void _start() {
    final generation = ++_generation;
    _loading = false;
    _failed = false;
    _error = null;
    final message = widget.message;
    final ref = message.previewRef;
    if (ref == null) return;
    if (_bytes != null) return;
    final cached = widget.loader.cached(ref);
    if (cached != null) {
      _bytes = cached;
      return;
    }
    if (widget.sendStatus != null) return;
    // Without a poster thumbnail the only blob is the whole video, which
    // cannot be drawn as an image; don't download it just to fail decoding.
    if (message.mediaType == MessageType.video &&
        message.mediaMeta?.thumbRef == null) {
      return;
    }
    _loading = true;
    unawaited(_load(message, ref, generation));
  }

  Future<void> _load(ChatMessage message, String ref, int generation) async {
    try {
      final bytes = await widget.loader.load(
        threadId: message.threadId,
        storagePath: ref,
        senderId: message.senderId,
      );
      if (!mounted || generation != _generation || _bytes != null) {
        bytes.fillRange(0, bytes.length, 0);
        return;
      }
      setState(() {
        _bytes = bytes;
        _loading = false;
        _failed = bytes.isEmpty;
      });
    } catch (error) {
      if (!mounted || generation != _generation || _bytes != null) return;
      setState(() {
        _loading = false;
        _failed = true;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.message.mediaMeta;
    // Reserve the final size up front using the clear-text dimensions, so the
    // bubble does not jump when the decrypted image arrives.
    const width = 220.0;
    final height = widget.message.mediaType == MessageType.sticker
        ? width
        : (width / (meta?.aspectRatio ?? 4 / 3)).clamp(80.0, 320.0);

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          height: height,
          child: _buildImage(width, height),
        ),
      ),
    );
  }

  Widget _buildUploadOverlay() {
    final status = widget.sendStatus;
    if (status == null) return const SizedBox.shrink();
    final progress = status.isIndeterminate ? null : status.progress;
    final percent = (status.progress * 100).clamp(0, 100).toInt();

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: 36,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 3.5,
                    color: Colors.white,
                    backgroundColor: Colors.white24,
                  ),
                  if (widget.onCancel != null)
                    GestureDetector(
                      onTap: widget.onCancel,
                      child: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              status.isIndeterminate ? status.label : '$percent%',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImage(double width, double height) {
    // Still uploading: no object exists yet, so show a neutral tile that the
    // progress overlay sits on.
    if (_bytes == null && !_loading && !_failed) {
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black26),
          if (widget.sendStatus != null)
            _buildUploadOverlay()
          else if (widget.message.mediaType == MessageType.video &&
              widget.message.mediaRef != null)
            const Center(
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.play_arrow, color: Colors.white),
              ),
            ),
        ],
      );
    }
    if (_loading) {
      return const ColoredBox(
        color: Colors.black26,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_failed || _bytes == null || _bytes!.isEmpty) {
      _scheduleRetry();
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: chatMediaRequiresAction(_error) ? widget.onTap : _retryNow,
        child: ColoredBox(
          color: Colors.black26,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (chatMediaFailureMessage(_error) case final detail?)
                      Text(
                        detail,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    if (!chatMediaRequiresAction(_error))
                      const Icon(
                        Icons.refresh_rounded,
                        color: Colors.white70,
                        size: 36,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (width * pixelRatio).ceil().clamp(1, 1024);
    final cacheHeight = (height * pixelRatio).ceil().clamp(1, 1024);
    if (_previewImage?.width != cacheWidth ||
        _previewImage?.height != cacheHeight) {
      final previous = _previewImage;
      if (previous != null) unawaited(previous.evict());
      // Image.memory's cache sizing uses ResizeImage too, but fit also
      // preserves the source aspect ratio when the bubble crops tall photos.
      _previewImage = ResizeImage(
        MemoryImage(_bytes!),
        width: cacheWidth,
        height: cacheHeight,
        policy: ResizeImagePolicy.fit,
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image(
          image: _previewImage!,
          fit:
              widget.message.mediaType == MessageType.gif ||
                  widget.message.mediaType == MessageType.sticker
              ? BoxFit.contain
              : BoxFit.cover,
          // Videos have no decodable poster frame yet; show a
          // neutral tile under the play button instead.
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Colors.black54,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'In-app preview unavailable. You can access this attachment securely from the vault.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
        ),
        if (widget.sendStatus != null) _buildUploadOverlay(),
        if (widget.message.mediaType == MessageType.video &&
            widget.sendStatus == null)
          const Center(
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: Icon(Icons.play_arrow, color: Colors.white),
            ),
          ),
      ],
    );
  }
}

/// Renders an encrypted document attachment and opens it on tap.
///
/// Supported media uses in-app memory viewers; other formats remain storable.
class ChatDocumentTile extends StatefulWidget {
  const ChatDocumentTile({
    super.key,
    required this.message,
    required this.loader,
    required this.textColor,
    this.sendStatus,
    this.onCancel,
    this.service = const AndroidChatSecureMediaService(),
  });

  final ChatMessage message;
  final ChatMediaLoader loader;
  final Color textColor;
  final AndroidChatSecureMediaService service;

  /// Progress while the document is being sent, null once it is sent.
  final MediaSendStatus? sendStatus;

  /// Stops the send while [sendStatus] is showing.
  final VoidCallback? onCancel;

  @override
  State<ChatDocumentTile> createState() => _ChatDocumentTileState();
}

class _ChatDocumentTileState extends State<ChatDocumentTile> {
  bool _opening = false;
  int _generation = 0;
  bool _nativeViewing = false;

  void _closeNativeViewer([AndroidChatSecureMediaService? service]) {
    if (!_nativeViewing) return;
    _nativeViewing = false;
    unawaited(
      (service ?? widget.service).close().catchError((Object error) {
        debugPrint('Secure chat attachment cleanup unavailable: $error');
      }),
    );
  }

  @override
  void didUpdateWidget(ChatDocumentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.loader != widget.loader ||
        oldWidget.service != widget.service) {
      _closeNativeViewer(oldWidget.service);
      _generation++;
      _opening = false;
    }
  }

  @override
  void dispose() {
    _generation++;
    _closeNativeViewer();
    super.dispose();
  }

  Future<void> _open() async {
    final message = widget.message;
    final loader = widget.loader;
    final service = widget.service;
    final ref = message.mediaRef;
    if (ref == null || _opening) return;
    final generation = ++_generation;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _opening = true);
    Uint8List? bytes;
    try {
      await loader.retryFailedDownload(ref);
      if (!mounted || generation != _generation) return;
      bytes = await loader.fetchUncached(
        threadId: message.threadId,
        storagePath: ref,
        senderId: message.senderId,
      );
      if (!mounted || generation != _generation) return;
      final name = message.documentName ?? '';
      var mimeType = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
          ? lookupMimeType(name, headerBytes: bytes)
          : name.toLowerCase().endsWith('.pdf')
          ? 'application/pdf'
          : null;
      if (mimeType == 'application/ogg') {
        final namedType = lookupMimeType(name);
        mimeType = namedType?.startsWith('video/') == true
            ? namedType
            : 'audio/ogg';
      }
      if (mimeType?.startsWith('image/') == true) {
        await ChatImageViewerScreen.open(
          context,
          message: message,
          loader: loader,
          initialBytes: bytes,
        );
      } else if (mimeType == 'application/pdf' ||
          mimeType?.startsWith('video/') == true ||
          mimeType?.startsWith('audio/') == true) {
        _nativeViewing = true;
        try {
          if (mimeType == 'application/pdf') {
            await service.showPdf(bytes);
          } else if (mimeType!.startsWith('video/')) {
            await service.showVideo(bytes);
          } else {
            await service.showAudio(bytes);
          }
        } finally {
          if (generation == _generation) _nativeViewing = false;
        }
      } else {
        messenger?.showSnackBar(
          const SnackBar(
            content: Text(
              'Attachment downloaded securely. Preview unavailable for this format; you can move it to the vault.',
            ),
          ),
        );
      }
    } on PlatformException catch (error) {
      if (!mounted || generation != _generation) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            error.message ??
                'In-app preview unavailable. You can access this attachment securely from the vault.',
          ),
        ),
      );
    } on UnsupportedError {
      if (!mounted || generation != _generation) return;
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'In-app preview unavailable for this format. You can access it securely from the vault.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted || generation != _generation) return;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            chatMediaFailureMessage(e) ?? 'Could not open document: $e',
          ),
        ),
      );
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted && generation == _generation) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.message.documentName ?? 'Document';
    final size = widget.message.mediaMeta?.readableSize ?? '';
    final color = widget.textColor;
    final tile = InkWell(
      onTap: widget.message.mediaRef == null || widget.sendStatus != null
          ? null
          : _open,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: _opening
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.insert_drive_file_rounded,
                      color: color,
                      size: 32,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  if (size.isNotEmpty)
                    Text(
                      size,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        tile,
        if (widget.sendStatus != null)
          AttachmentUploadProgress(
            status: widget.sendStatus!,
            onCancel: widget.onCancel,
          )
        else if (_opening && widget.message.mediaRef != null)
          AttachmentDownloadProgress(
            loader: widget.loader,
            storagePath: widget.message.mediaRef!,
          ),
      ],
    );
  }
}
