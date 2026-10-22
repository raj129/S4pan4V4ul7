import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../domain/entities/chat_message.dart';
import '../widgets/chat_media_preview.dart';
import '../widgets/attachment_download_progress.dart';

/// Full-screen viewer for a chat photo, with pan, pinch and double-tap zoom.
///
/// The already-decrypted thumbnail is shown immediately while the full-size
/// image is fetched, so opening feels instant even on a slow connection.
class ChatImageViewerScreen extends StatefulWidget {
  const ChatImageViewerScreen({
    super.key,
    required this.message,
    required this.loader,
    this.initialBytes,
  });

  final ChatMessage message;
  final ChatMediaLoader loader;

  /// Borrowed authenticated bytes; the viewer copies them before displaying.
  final Uint8List? initialBytes;

  static Future<void> open(
    BuildContext context, {
    required ChatMessage message,
    required ChatMediaLoader loader,
    Uint8List? initialBytes,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => ChatImageViewerScreen(
          message: message,
          loader: loader,
          initialBytes: initialBytes,
        ),
        transitionsBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  State<ChatImageViewerScreen> createState() => _ChatImageViewerScreenState();
}

class _ChatImageViewerScreenState extends State<ChatImageViewerScreen>
    with SingleTickerProviderStateMixin {
  final _controller = TransformationController();
  late final AnimationController _animation;

  Animation<Matrix4>? _zoomAnimation;
  Future<Uint8List>? _full;
  Uint8List? _fullBytes;
  Uint8List? _thumbBytes;
  int _generation = 0;

  static const _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    _animation =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          final animation = _zoomAnimation;
          if (animation != null) _controller.value = animation.value;
        });
    widget.loader.addListener(_onMediaChanged);
    _loadFull();
  }

  void _loadFull() {
    final generation = ++_generation;
    final message = widget.message;
    final initialBytes = widget.initialBytes;
    if (initialBytes != null && initialBytes.isNotEmpty) {
      final owned = Uint8List.fromList(initialBytes);
      _fullBytes = owned;
      _full = Future.value(owned);
      return;
    }
    final thumbRef = message.previewRef;
    _thumbBytes ??= thumbRef == null ? null : widget.loader.cached(thumbRef);
    final ref = widget.message.mediaRef;
    _full = ref == null ? null : _acquireFull(message, ref, generation);
  }

  Future<Uint8List> _acquireFull(
    ChatMessage message,
    String ref,
    int generation,
  ) async {
    final bytes = await widget.loader.load(
      threadId: message.threadId,
      storagePath: ref,
      senderId: message.senderId,
    );
    if (!mounted || generation != _generation || _fullBytes != null) {
      bytes.fillRange(0, bytes.length, 0);
      return Uint8List(0);
    }
    if (bytes.isEmpty) throw StateError('Image is unavailable.');
    _fullBytes = bytes;
    return bytes;
  }

  void _onMediaChanged() {
    if (!mounted || _fullBytes != null) return;
    final thumbRef = widget.message.previewRef;
    final thumb = _thumbBytes != null || thumbRef == null
        ? null
        : widget.loader.cached(thumbRef);
    final ref = widget.message.mediaRef;
    final bytes = ref == null ? null : widget.loader.cached(ref);
    if (bytes == null && thumb == null) return;
    setState(() {
      if (thumb != null) _thumbBytes = thumb;
      if (bytes != null) {
        _fullBytes = bytes;
        _full = Future.value(bytes);
      }
    });
  }

  Future<void> _retryFull() async {
    final ref = widget.message.mediaRef;
    final generation = _generation;
    if (ref == null) return;
    try {
      await widget.loader.retryFailedDownload(ref);
      if (mounted && generation == _generation) setState(_loadFull);
    } catch (error) {
      if (mounted && generation == _generation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not retry download: $error')),
        );
      }
    }
  }

  @override
  void didUpdateWidget(ChatImageViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loader != widget.loader) {
      oldWidget.loader.removeListener(_onMediaChanged);
      widget.loader.addListener(_onMediaChanged);
    }
    if (oldWidget.message.mediaRef != widget.message.mediaRef ||
        oldWidget.message.threadId != widget.message.threadId ||
        oldWidget.message.messageId != widget.message.messageId ||
        oldWidget.message.senderId != widget.message.senderId ||
        oldWidget.message.previewRef != widget.message.previewRef ||
        oldWidget.initialBytes != widget.initialBytes ||
        oldWidget.loader != widget.loader) {
      _releaseBytes();
      _loadFull();
    }
  }

  @override
  void dispose() {
    widget.loader.removeListener(_onMediaChanged);
    _generation++;
    _releaseBytes();
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _releaseBytes() {
    for (final bytes in [_fullBytes, _thumbBytes]) {
      if (bytes == null) continue;
      unawaited(MemoryImage(bytes).evict());
      bytes.fillRange(0, bytes.length, 0);
    }
    _fullBytes = null;
    _thumbBytes = null;
  }

  void _handleDoubleTap(TapDownDetails details) {
    final zoomedIn = _controller.value.getMaxScaleOnAxis() > 1.01;
    final target = zoomedIn
        ? Matrix4.identity()
        : (Matrix4.identity()
            ..translateByDouble(
              -details.localPosition.dx * (_doubleTapScale - 1),
              -details.localPosition.dy * (_doubleTapScale - 1),
              0,
              1,
            )
            ..scaleByDouble(
              _doubleTapScale,
              _doubleTapScale,
              _doubleTapScale,
              1,
            ));
    _zoomAnimation = Matrix4Tween(
      begin: _controller.value,
      end: target,
    ).animate(CurvedAnimation(parent: _animation, curve: Curves.easeOut));
    _animation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onDoubleTapDown: _handleDoubleTap,
              // InteractiveViewer needs the double-tap gesture to be claimed
              // here; the work happens in onDoubleTapDown, which carries the
              // tap position.
              onDoubleTap: () {},
              child: InteractiveViewer(
                transformationController: _controller,
                minScale: 1,
                maxScale: 5,
                child: Center(child: _buildImage(_thumbBytes)),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 4,
            left: 4,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
              tooltip: 'Close',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImage(Uint8List? thumb) {
    final future = _full;
    if (future == null) {
      return const Icon(
        Icons.broken_image_outlined,
        color: Colors.white54,
        size: 48,
      );
    }
    return FutureBuilder<Uint8List>(
      key: ValueKey(_generation),
      future: future,
      builder: (context, snap) {
        if (snap.hasData && snap.data!.isNotEmpty) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.broken_image_outlined, color: Colors.white54),
                Text(
                  'In-app preview unavailable for this image. You can access it securely from the vault.',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chatMediaFailureMessage(snap.error) case final detail?)
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                if (!chatMediaRequiresAction(snap.error))
                  IconButton(
                    iconSize: 48,
                    color: Colors.white54,
                    tooltip: 'Retry',
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _retryFull,
                  ),
              ],
            ),
          );
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            if (thumb != null)
              Image.memory(
                thumb,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              )
            else
              const SizedBox.shrink(),
            Material(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: AttachmentDownloadProgress(
                  loader: widget.loader,
                  storagePath: widget.message.mediaRef ?? '',
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
