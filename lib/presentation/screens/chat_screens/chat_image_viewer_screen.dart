import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../domain/entities/chat_message.dart';
import '../../widgets/chat/chat_media_preview.dart';

/// Full-screen viewer for a chat photo, with pan, pinch and double-tap zoom.
///
/// The already-decrypted thumbnail is shown immediately while the full-size
/// image is fetched, so opening feels instant even on a slow connection.
class ChatImageViewerScreen extends StatefulWidget {
  const ChatImageViewerScreen({
    super.key,
    required this.message,
    required this.loader,
  });

  final ChatMessage message;
  final ChatMediaLoader loader;

  static Future<void> open(
    BuildContext context, {
    required ChatMessage message,
    required ChatMediaLoader loader,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) =>
            ChatImageViewerScreen(message: message, loader: loader),
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
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..addListener(() => _controller.value = _zoomAnimation!.value);

  Animation<Matrix4>? _zoomAnimation;
  Future<Uint8List>? _full;

  static const _doubleTapScale = 2.5;

  @override
  void initState() {
    super.initState();
    final ref = widget.message.mediaRef;
    if (ref != null) {
      _full = widget.loader.load(
        threadId: widget.message.threadId,
        storagePath: ref,
      );
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
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
    final thumbRef = widget.message.previewRef;
    final thumb = thumbRef == null ? null : widget.loader.cached(thumbRef);

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
                child: Center(child: _buildImage(thumb)),
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
      future: future,
      builder: (context, snap) {
        if (snap.hasData && snap.data!.isNotEmpty) {
          return Image.memory(snap.data!, fit: BoxFit.contain);
        }
        if (snap.hasError) {
          return const Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 48,
          );
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            if (thumb != null)
              Image.memory(thumb, fit: BoxFit.contain)
            else
              const SizedBox.shrink(),
            const CircularProgressIndicator(color: Colors.white70),
          ],
        );
      },
    );
  }
}
