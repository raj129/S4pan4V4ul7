import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../application/media/android_chat_secure_media_service.dart';

/// Launches the in-app memory-only native player with modern voice-note styling.
class ChatAudioPlayer extends StatefulWidget {
  const ChatAudioPlayer({
    super.key,
    required this.loadBytes,
    this.service = const AndroidChatSecureMediaService(),
    this.loading,
    this.duration,
  });

  final Future<Uint8List> Function() loadBytes;
  final AndroidChatSecureMediaService service;
  final Widget? loading;
  final String? duration;

  @override
  State<ChatAudioPlayer> createState() => _ChatAudioPlayerState();
}

class _ChatAudioPlayerState extends State<ChatAudioPlayer>
    with SingleTickerProviderStateMixin {
  bool _busy = false;
  String? _error;
  late final AnimationController _anim;

  // Waveform bars heights for modern aesthetic
  static const _barHeights = [
    8.0, 14.0, 22.0, 16.0, 10.0, 26.0, 18.0, 12.0, 28.0, 20.0,
    14.0, 24.0, 16.0, 10.0, 20.0, 14.0, 26.0, 18.0, 12.0, 22.0,
    16.0, 10.0, 14.0, 8.0,
  ];

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    _anim.repeat(reverse: true);
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
      if (mounted) {
        _anim.stop();
        _anim.reset();
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _busy ? null : _play,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cs.outlineVariant.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Play button circular avatar
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.3),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: _busy
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  cs.onPrimary,
                                ),
                              ),
                            )
                          : Icon(
                              Icons.play_arrow_rounded,
                              color: cs.onPrimary,
                              size: 26,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Waveform bars
                  AnimatedBuilder(
                    animation: _anim,
                    builder: (context, child) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_barHeights.length, (i) {
                          final h = _busy
                              ? (_barHeights[i] * (0.6 + 0.4 * _anim.value))
                              : _barHeights[i];
                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 1.5),
                            width: 3,
                            height: h,
                            decoration: BoxDecoration(
                              color: _busy
                                  ? cs.primary
                                  : cs.onSurfaceVariant.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        }),
                      );
                    },
                  ),
                  const SizedBox(width: 10),
                  // Duration or label
                  Text(
                    widget.duration ?? 'Voice',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, left: 8),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.error,
                  fontSize: 11,
                ),
              ),
            ),
          if (_busy && widget.loading != null) widget.loading!,
        ],
      ),
    );
  }
}
