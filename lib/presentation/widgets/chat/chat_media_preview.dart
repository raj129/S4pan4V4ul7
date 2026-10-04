import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/services/chat_media_loader.dart';
import '../../../application/services/android_chat_secure_media_service.dart';
import '../../../domain/entities/chat_message.dart';
import '../../state/chat/media_send_status.dart';

export '../../../application/services/chat_media_loader.dart';

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
  Future<Uint8List>? _future;
  int _attempt = 0;

  static const _maxAutoRetries = 3;

  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    widget.loader.addListener(_onLoaderChanged);
    _future = _start();
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
        oldWidget.loader != widget.loader ||
        (oldWidget.sendStatus != null && widget.sendStatus == null)) {
      _attempt = 0;
      _retryTimer?.cancel();
      _future = _start();
    }
  }

  void _onLoaderChanged() {
    final ref = widget.message.previewRef;
    final bytes = ref == null ? null : widget.loader.cached(ref);
    if (!mounted || bytes == null) return;
    _retryTimer?.cancel();
    setState(() {
      _future = Future.value(bytes);
    });
  }

  @override
  void dispose() {
    widget.loader.removeListener(_onLoaderChanged);
    _retryTimer?.cancel();
    super.dispose();
  }

  /// A failed load would otherwise stay broken until the chat is reopened.
  void _scheduleRetry() {
    if (_attempt >= _maxAutoRetries || _retryTimer?.isActive == true) return;
    _attempt++;
    _retryTimer = Timer(Duration(seconds: 2 * _attempt), _retryNow);
  }

  void _retryNow() {
    if (!mounted) return;
    _retryTimer?.cancel();
    setState(() {
      _future = _start();
    });
  }

  /// Null while an outgoing attachment is still uploading: there is no object
  /// to fetch yet, and the bubble shows the upload placeholder instead.
  Future<Uint8List>? _start() {
    final message = widget.message;
    final ref = message.previewRef;
    if (ref == null) return null;
    final cached = widget.loader.cached(ref);
    if (cached != null) return Future.value(cached);
    if (widget.sendStatus != null) return null;
    // Without a poster thumbnail the only blob is the whole video, which
    // cannot be drawn as an image; don't download it just to fail decoding.
    if (message.mediaType == MessageType.video &&
        message.mediaMeta?.thumbRef == null) {
      return null;
    }
    return widget.loader.load(threadId: message.threadId, storagePath: ref);
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.message.mediaMeta;
    // Reserve the final size up front using the clear-text dimensions, so the
    // bubble does not jump when the decrypted image arrives.
    const width = 220.0;
    final height = (width / (meta?.aspectRatio ?? 4 / 3)).clamp(80.0, 320.0);

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(width: width, height: height, child: _buildImage()),
      ),
    );
  }

  Widget _buildImage() {
    final future = _future;
    // Still uploading: no object exists yet, so show a neutral tile that the
    // progress overlay sits on.
    if (future == null) {
      return ColoredBox(
        color: Colors.black26,
        child:
            widget.message.mediaType == MessageType.video &&
                widget.message.mediaRef != null &&
                widget.sendStatus == null
            ? const Center(
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.play_arrow, color: Colors.white),
                ),
              )
            : const SizedBox.expand(),
      );
    }
    return FutureBuilder<Uint8List>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
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
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          _scheduleRetry();
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _retryNow,
            child: const ColoredBox(
              color: Colors.black26,
              child: Center(
                child: Icon(
                  Icons.refresh_rounded,
                  color: Colors.white70,
                  size: 36,
                ),
              ),
            ),
          );
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Image.memory(
              snap.data!,
              fit: BoxFit.cover,
              // Videos have no decodable poster frame yet; show a
              // neutral tile under the play button instead.
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Colors.black54,
                child: Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white70,
                  ),
                ),
              ),
            ),
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
      },
    );
  }
}

/// Renders an encrypted document attachment and opens it on tap.
///
/// PDF viewing uses memory only; other formats remain securely storable.
class ChatDocumentTile extends StatefulWidget {
  const ChatDocumentTile({
    super.key,
    required this.message,
    required this.loader,
    required this.textColor,
    this.sendStatus,
    this.onCancel,
  });

  final ChatMessage message;
  final ChatMediaLoader loader;
  final Color textColor;

  /// Progress while the document is being sent, null once it is sent.
  final MediaSendStatus? sendStatus;

  /// Stops the send while [sendStatus] is showing.
  final VoidCallback? onCancel;

  @override
  State<ChatDocumentTile> createState() => _ChatDocumentTileState();
}

class _ChatDocumentTileState extends State<ChatDocumentTile> {
  bool _opening = false;

  Future<void> _open() async {
    final ref = widget.message.mediaRef;
    if (ref == null || _opening) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (!(widget.message.documentName?.toLowerCase().endsWith('.pdf') ??
        false)) {
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Preview unavailable for this format. You can move it to the vault.',
          ),
        ),
      );
      return;
    }
    setState(() => _opening = true);
    Uint8List? bytes;
    try {
      bytes = await widget.loader.fetchUncached(
        threadId: widget.message.threadId,
        storagePath: ref,
      );
      if (!mounted) return;
      await const AndroidChatSecureMediaService().showPdf(bytes);
    } on PlatformException catch (error) {
      messenger?.showSnackBar(
        SnackBar(content: Text(error.message ?? 'PDF preview unavailable.')),
      );
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not open document: $e')),
      );
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.message.documentName ?? 'Document';
    final size = widget.message.mediaMeta?.readableSize ?? '';
    final color = widget.textColor;
    return InkWell(
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
  }
}
