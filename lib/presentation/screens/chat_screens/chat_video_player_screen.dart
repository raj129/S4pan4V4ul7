import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../domain/entities/chat_message.dart';
import '../../widgets/chat/chat_media_preview.dart';

/// Full-screen player for an encrypted chat video.
///
/// The player needs a real file, so the decrypted bytes are written to a
/// private temp folder for the duration of playback and deleted on close.
class ChatVideoPlayerScreen extends StatefulWidget {
  const ChatVideoPlayerScreen({
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
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => ChatVideoPlayerScreen(message: message, loader: loader),
      ),
    );
  }

  @override
  State<ChatVideoPlayerScreen> createState() => _ChatVideoPlayerScreenState();
}

class _ChatVideoPlayerScreenState extends State<ChatVideoPlayerScreen> {
  VideoPlayerController? _controller;
  File? _file;
  Object? _error;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (_error != null) setState(() => _error = null);
    try {
      final ref = widget.message.mediaRef;
      if (ref == null) throw StateError('Video is not available yet.');
      final bytes = await widget.loader.fetchUncached(
        threadId: widget.message.threadId,
        storagePath: ref,
      );
      final tmp = await getTemporaryDirectory();
      final dir = Directory(p.join(tmp.path, 'chat_video'));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, '${widget.message.messageId}.mp4'));
      await file.writeAsBytes(bytes, flush: true);
      _file = file;

      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      await controller.play();
      setState(() => _controller = controller);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _controller;
    final file = _file;
    Future<void>(() async {
      await controller?.dispose();
      try {
        if (file != null && await file.exists()) await file.delete();
      } catch (_) {}
    });
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(child: _body(controller)),
    );
  }

  Widget _body(VideoPlayerController? controller) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Could not play this video',
              style: TextStyle(color: Colors.white70),
            ),
            TextButton(onPressed: _prepare, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white70),
      );
    }
    final value = controller.value;
    return Column(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () =>
                value.isPlaying ? controller.pause() : controller.play(),
            child: Center(
              child: AspectRatio(
                aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
        VideoProgressIndicator(
          controller,
          allowScrubbing: true,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
        Row(
          children: [
            IconButton(
              color: Colors.white,
              icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
              onPressed: () =>
                  value.isPlaying ? controller.pause() : controller.play(),
            ),
            Text(
              '${_format(value.position)} / ${_format(value.duration)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ],
    );
  }
}
