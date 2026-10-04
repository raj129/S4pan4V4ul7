import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../application/services/android_chat_secure_media_service.dart';

/// Launches the in-app memory-only native player, never an external app.
class ChatAudioPlayer extends StatefulWidget {
  const ChatAudioPlayer({
    super.key,
    required this.loadBytes,
    this.service = const AndroidChatSecureMediaService(),
  });

  final Future<Uint8List> Function() loadBytes;
  final AndroidChatSecureMediaService service;

  @override
  State<ChatAudioPlayer> createState() => _ChatAudioPlayerState();
}

class _ChatAudioPlayerState extends State<ChatAudioPlayer> {
  bool _busy = false;
  String? _error;

  Future<void> _play() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    Uint8List? bytes;
    try {
      bytes = await widget.loadBytes();
      if (!mounted) return;
      await widget.service.showAudio(bytes);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Audio unavailable.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not play audio. Try again.');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      TextButton.icon(
        onPressed: _busy ? null : _play,
        icon: _busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.play_circle_outline),
        label: const Text('Play audio'),
      ),
      if (_error != null) Text(_error!),
    ],
  );
}
