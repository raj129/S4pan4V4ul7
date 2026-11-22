import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:photo_vault/core/widgets/secure_audio_player.dart';
import '../../application/media/android_chat_secure_media_service.dart';

/// Inline Material 3 voice/audio player backed by in-memory native ExoPlayer.
class ChatAudioPlayer extends StatefulWidget {
  const ChatAudioPlayer({
    super.key,
    required this.loadBytes,
    this.service = const AndroidChatSecureMediaService(),
    this.controller,
    this.loading,
    this.duration,
  });

  final Future<Uint8List> Function() loadBytes;
  final AndroidChatSecureMediaService service;
  final SecureAudioController? controller;
  final Widget? loading;
  final String? duration;

  @override
  State<ChatAudioPlayer> createState() => _ChatAudioPlayerState();
}

class _ChatAudioPlayerState extends State<ChatAudioPlayer> {
  late final SecureAudioController _controller;
  late final String _sessionId;
  bool _fetching = false;
  String? _error;

  static const _barHeights = [
    8.0,
    14.0,
    22.0,
    16.0,
    10.0,
    26.0,
    18.0,
    12.0,
    28.0,
    20.0,
    14.0,
    24.0,
    16.0,
    10.0,
    20.0,
    14.0,
    26.0,
    18.0,
    12.0,
    22.0,
    16.0,
    10.0,
    14.0,
    8.0,
  ];

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SecureAudioController.instance;
    _sessionId = _controller.nextSessionId('chat-audio');
  }

  @override
  void dispose() {
    if (_controller.state.sessionId == _sessionId) {
      unawaited(_controller.stop(_sessionId).catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> _onPlayPauseTap(SecureAudioState state) async {
    if (_fetching) return;
    if (state.status == SecureAudioPlaybackStatus.playing) {
      await _controller.pause(_sessionId);
      return;
    }
    if (state.status == SecureAudioPlaybackStatus.paused ||
        state.status == SecureAudioPlaybackStatus.ended) {
      await _controller.resume(_sessionId);
      return;
    }

    setState(() {
      _fetching = true;
      _error = null;
    });
    Uint8List? bytes;
    try {
      bytes = await widget.loadBytes();
      if (!mounted) return;
      await _controller.playBytes(bytes, sessionId: _sessionId);
    } on ArgumentError catch (e) {
      if (mounted) {
        setState(() => _error = e.message?.toString() ?? 'Audio too large.');
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'Audio unavailable.');
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not play audio. Try again.');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _fetching = false);
    }
  }

  void _seekFromLocalDx(double dx, double width, Duration duration) {
    if (width <= 0 || duration <= Duration.zero) return;
    final fraction = (dx / width).clamp(0.0, 1.0);
    final target = Duration(
      milliseconds: (duration.inMilliseconds * fraction).round(),
    );
    unawaited(_controller.seekTo(_sessionId, target));
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final state = _controller.stateFor(_sessionId);
        final isActive = state.isActive;
        final isPlaying = state.status == SecureAudioPlaybackStatus.playing;
        final isLoading =
            _fetching || state.status == SecureAudioPlaybackStatus.loading;
        final duration = state.duration;
        final progress = duration > Duration.zero
            ? (state.position.inMilliseconds / duration.inMilliseconds)
                  .clamp(0.0, 1.0)
            : 0.0;
        final errorText = _error ?? state.error;

        final timeLabel = isActive
            ? _formatDuration(state.position)
            : (widget.duration ?? 'Voice');

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isActive
                        ? cs.primary.withValues(alpha: 0.35)
                        : cs.outlineVariant.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: isLoading ? null : () => _onPlayPauseTap(state),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: cs.primary,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: cs.primary.withValues(alpha: 0.28),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: isLoading
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
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: cs.onPrimary,
                                    size: 26,
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Interactive waveform scrubber
                    LayoutBuilder(
                      builder: (context, constraints) {
                        const barWidth = 3.0;
                        const barMargin = 1.5;
                        final totalWidth =
                            _barHeights.length * (barWidth + barMargin * 2);
                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: isActive && duration > Duration.zero
                              ? (d) => _seekFromLocalDx(
                                  d.localPosition.dx,
                                  totalWidth,
                                  duration,
                                )
                              : null,
                          onHorizontalDragUpdate:
                              isActive && duration > Duration.zero
                              ? (d) => _seekFromLocalDx(
                                  d.localPosition.dx,
                                  totalWidth,
                                  duration,
                                )
                              : null,
                          child: SizedBox(
                            height: 30,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(_barHeights.length, (i) {
                                final barProgress =
                                    (i + 1) / _barHeights.length;
                                final filled = isActive &&
                                    progress >= barProgress - 0.02;
                                return AnimatedContainer(
                                  duration: const Duration(milliseconds: 120),
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: barMargin,
                                  ),
                                  width: barWidth,
                                  height: _barHeights[i],
                                  decoration: BoxDecoration(
                                    color: filled
                                        ? cs.primary
                                        : cs.onSurfaceVariant.withValues(
                                            alpha: 0.45,
                                          ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                );
                              }),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          timeLabel,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: isActive
                                ? cs.primary
                                : cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (isActive)
                          GestureDetector(
                            onTap: () => _controller.cycleSpeed(_sessionId),
                            child: Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${state.speed}x',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: cs.onPrimaryContainer,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 10,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (errorText != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 8),
                  child: Text(
                    errorText,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.error,
                      fontSize: 11,
                    ),
                  ),
                ),
              if (_fetching && widget.loading != null) widget.loading!,
            ],
          ),
        );
      },
    );
  }
}
