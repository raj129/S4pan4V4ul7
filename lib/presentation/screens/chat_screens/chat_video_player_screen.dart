import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/services/android_chat_secure_media_service.dart';
import '../../../application/services/chat_media_loader.dart';
import '../../../domain/entities/chat_message.dart';

/// Loads authenticated bytes, then opens an in-app native memory-data player.
class ChatVideoPlayerScreen extends StatefulWidget {
  const ChatVideoPlayerScreen({
    super.key,
    required this.message,
    required this.loader,
    this.service = const AndroidChatSecureMediaService(),
  });

  final ChatMessage message;
  final ChatMediaLoader loader;
  final AndroidChatSecureMediaService service;

  static Future<void> open(
    BuildContext context, {
    required ChatMessage message,
    required ChatMediaLoader loader,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ChatVideoPlayerScreen(message: message, loader: loader),
    ),
  );

  @override
  State<ChatVideoPlayerScreen> createState() => _ChatVideoPlayerScreenState();
}

class _ChatVideoPlayerScreenState extends State<ChatVideoPlayerScreen> {
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    Uint8List? bytes;
    try {
      final ref = widget.message.mediaRef;
      if (ref == null) throw StateError('Video is not available yet.');
      bytes = await widget.loader.fetchUncached(
        threadId: widget.message.threadId,
        storagePath: ref,
      );
      if (!mounted) return;
      await widget.service.showVideo(bytes);
      if (mounted) Navigator.of(context).pop();
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Video unavailable.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not play this video.');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    unawaited(
      widget.service.close().catchError((Object _) {
        debugPrint('Secure chat video cleanup unavailable.');
      }),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
    ),
    body: Center(
      child: _error == null
          ? const CircularProgressIndicator()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, style: const TextStyle(color: Colors.white70)),
                TextButton(onPressed: _prepare, child: const Text('Retry')),
              ],
            ),
    ),
  );
}
