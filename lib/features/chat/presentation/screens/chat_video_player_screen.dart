import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/media/android_chat_secure_media_service.dart';
import '../../application/media/chat_media_loader.dart';
import '../../domain/entities/chat_message.dart';
import '../widgets/attachment_download_progress.dart';
import '../widgets/chat_media_preview.dart'
    show chatMediaFailureMessage, chatMediaRequiresAction;

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
  bool _requiresAction = false;
  bool _busy = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    if (_busy) return;
    final generation = ++_generation;
    final message = widget.message;
    final loader = widget.loader;
    final service = widget.service;
    setState(() {
      _busy = true;
      _error = null;
      _requiresAction = false;
    });
    Uint8List? bytes;
    try {
      final ref = message.mediaRef;
      if (ref == null) throw StateError('Video is not available yet.');
      await loader.retryFailedDownload(ref);
      if (!mounted || generation != _generation) return;
      bytes = await loader.fetchUncached(
        threadId: message.threadId,
        storagePath: ref,
        senderId: message.senderId,
      );
      if (!mounted || generation != _generation) return;
      await service.showVideo(bytes);
      if (mounted && generation == _generation) Navigator.of(context).pop();
    } on PlatformException catch (e) {
      if (mounted && generation == _generation) {
        _requiresAction = chatMediaRequiresAction(e);
        setState(
          () => _error =
              e.message ??
              'In-app video playback unavailable. You can access it securely from the vault.',
        );
      }
    } on UnsupportedError {
      if (mounted && generation == _generation) {
        setState(
          () => _error =
              'In-app video playback unavailable. You can access it securely from the vault.',
        );
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _requiresAction = chatMediaRequiresAction(error);
          _error =
              chatMediaFailureMessage(error) ?? 'Could not play this video.';
        });
      }
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  void didUpdateWidget(ChatVideoPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.loader != widget.loader ||
        oldWidget.service != widget.service) {
      _generation++;
      _busy = false;
      _prepare();
    }
  }

  @override
  void dispose() {
    _generation++;
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
          ? AttachmentDownloadProgress(
              loader: widget.loader,
              storagePath: widget.message.mediaRef ?? '',
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, style: const TextStyle(color: Colors.white70)),
                if (!_requiresAction &&
                    widget.loader.downloads?.job(
                          widget.message.mediaRef ?? '',
                        ) !=
                        null)
                  AttachmentDownloadProgress(
                    loader: widget.loader,
                    storagePath: widget.message.mediaRef ?? '',
                    onRetry: _prepare,
                  )
                else if (!_requiresAction)
                  TextButton(onPressed: _prepare, child: const Text('Retry')),
              ],
            ),
    ),
  );
}
