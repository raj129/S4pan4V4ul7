import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:photo_vault/features/chat/application/media/android_chat_secure_media_service.dart';

const _inlineMediaViewType = 'photo_vault/inline_media';

/// Modern Material 3 in-memory video player backed by Android ExoPlayer.
///
/// Never writes decrypted bytes to disk and enforces the in-memory size limit
/// before dispatching across the platform channel.
class SecureVideoPlayer extends StatefulWidget {
  const SecureVideoPlayer({
    super.key,
    required this.bytes,
    this.title = 'Video',
    this.showTopBar = true,
    this.autoPlay = true,
    this.initialLoop = false,
    this.onClose,
    this.trailingActions = const [],
  });

  final Uint8List bytes;
  final String title;
  final bool showTopBar;
  final bool autoPlay;
  final bool initialLoop;
  final VoidCallback? onClose;
  final List<Widget> trailingActions;

  @override
  State<SecureVideoPlayer> createState() => _SecureVideoPlayerState();
}

class _SecureVideoPlayerState extends State<SecureVideoPlayer>
    with WidgetsBindingObserver {
  static const _speeds = [0.5, 1.0, 1.25, 1.5, 2.0];

  MethodChannel? _channel;
  Timer? _hideTimer;
  Timer? _seekBadgeTimer;

  bool _controlsVisible = true;
  bool _isPlaying = false;
  bool _isBuffering = true;
  bool _isEnded = false;
  bool _isMuted = false;
  bool _isLooping = false;
  bool _isCoverFit = false;
  bool _isDragging = false;
  int _speedIndex = 1; // 1.0x
  int _viewRevision = 0;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffered = Duration.zero;
  double? _dragValueMs;

  String? _error;
  int? _seekFeedbackSeconds; // -10 or +10

  bool get _useNative => defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _isLooping = widget.initialLoop;
    WidgetsBinding.instance.addObserver(this);
    _validateSize();
    _scheduleHide();
  }

  void _validateSize() {
    if (widget.bytes.isEmpty) {
      _error = 'Video data is empty.';
      return;
    }
    if (widget.bytes.length > AndroidChatSecureMediaService.maxBytes) {
      _error =
          'This video is larger than the 64 MB in-memory playback limit. '
          'Export it to play externally.';
    }
  }

  @override
  void didUpdateWidget(SecureVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _closeChannel();
      _error = null;
      _position = Duration.zero;
      _duration = Duration.zero;
      _buffered = Duration.zero;
      _isPlaying = false;
      _isBuffering = true;
      _isEnded = false;
      _validateSize();
      _viewRevision++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_invoke('pause'));
    } else if (state == AppLifecycleState.resumed && _error == null) {
      // Native plugin closes inline views on onActivityStopped; recreate cleanly
      // if the view was closed while backgrounded.
      unawaited(_checkAndRecoverAfterResume());
    }
  }

  Future<void> _checkAndRecoverAfterResume() async {
    final channel = _channel;
    if (channel == null) return;
    try {
      final state = await channel.invokeMapMethod<Object?, Object?>('getState');
      if (!mounted) return;
      if (state?['status'] == 'closed') {
        setState(() {
          _channel = null;
          _isBuffering = true;
          _isPlaying = false;
          _viewRevision++;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _channel = null;
        _isBuffering = true;
        _isPlaying = false;
        _viewRevision++;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    _seekBadgeTimer?.cancel();
    _closeChannel();
    super.dispose();
  }

  void _closeChannel() {
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      channel.setMethodCallHandler(null);
      unawaited(channel.invokeMethod<void>('close').catchError((Object _) {}));
    }
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_inlineMediaViewType/$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      switch (call.method) {
        case 'playingChanged':
          final playing = call.arguments == true;
          setState(() {
            _isPlaying = playing;
            if (playing) _isEnded = false;
          });
          if (playing) {
            _scheduleHide();
          } else {
            _hideTimer?.cancel();
            setState(() => _controlsVisible = true);
          }
          break;
        case 'positionChanged':
          if (call.arguments is Map && !_isDragging) {
            final map = Map<Object?, Object?>.from(call.arguments as Map);
            final posMs = (map['positionMs'] as num?)?.toInt() ?? 0;
            final durMs = (map['durationMs'] as num?)?.toInt() ?? 0;
            final bufMs = (map['bufferedMs'] as num?)?.toInt() ?? 0;
            final playing = map['playing'] as bool?;
            setState(() {
              _position = Duration(milliseconds: posMs);
              if (durMs > 0) _duration = Duration(milliseconds: durMs);
              _buffered = Duration(milliseconds: bufMs);
              if (playing != null) _isPlaying = playing;
            });
          }
          break;
        case 'ended':
          _hideTimer?.cancel();
          setState(() {
            _isPlaying = false;
            _isEnded = true;
            _isBuffering = false;
            _controlsVisible = true;
            if (_duration > Duration.zero) _position = _duration;
          });
          break;
        case 'statusChanged':
          if (call.arguments is Map) {
            final map = Map<Object?, Object?>.from(call.arguments as Map);
            final status = map['status'] as String?;
            if (status == 'error') {
              setState(() {
                _error =
                    (map['message'] as String?) ??
                    'Video could not be played on this device.';
                _isBuffering = false;
                _isPlaying = false;
              });
            } else if (status == 'buffering') {
              setState(() => _isBuffering = true);
            } else if (status == 'ready') {
              setState(() => _isBuffering = false);
            }
          }
          break;
      }
    });
    unawaited(_syncInitialState(channel));
  }

  Future<void> _syncInitialState(MethodChannel channel) async {
    try {
      final state = await channel.invokeMapMethod<Object?, Object?>('getState');
      if (!mounted || state == null) return;
      final status = state['status'] as String?;
      final posMs = (state['positionMs'] as num?)?.toInt() ?? 0;
      final durMs = (state['durationMs'] as num?)?.toInt() ?? 0;
      setState(() {
        _isBuffering = status == 'loading' || status == 'buffering';
        _isPlaying = state['playing'] == true;
        _position = Duration(milliseconds: posMs);
        if (durMs > 0) _duration = Duration(milliseconds: durMs);
      });
    } catch (_) {}
  }

  Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    final channel = _channel;
    if (channel == null) return;
    try {
      await channel.invokeMethod<void>(method, args);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Video playback error.');
      }
    }
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_isPlaying || _isDragging) return;
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isPlaying && !_isDragging) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  Future<void> _togglePlayPause() async {
    await _invoke('toggle');
    _scheduleHide();
  }

  Future<void> _seekBy(int seconds) async {
    final totalMs = _duration.inMilliseconds;
    final targetMs = (_position.inMilliseconds + seconds * 1000).clamp(
      0,
      totalMs > 0 ? totalMs : 0,
    );
    setState(() {
      _position = Duration(milliseconds: targetMs);
      _seekFeedbackSeconds = seconds;
      _isEnded = false;
    });
    _seekBadgeTimer?.cancel();
    _seekBadgeTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekFeedbackSeconds = null);
    });
    await _invoke('seekTo', {'positionMs': targetMs});
    _scheduleHide();
  }

  Future<void> _cycleSpeed() async {
    _speedIndex = (_speedIndex + 1) % _speeds.length;
    final speed = _speeds[_speedIndex];
    setState(() {});
    await _invoke('setSpeed', {'speed': speed});
    _scheduleHide();
  }

  Future<void> _toggleMute() async {
    setState(() => _isMuted = !_isMuted);
    await _invoke('setVolume', {'volume': _isMuted ? 0.0 : 1.0});
    _scheduleHide();
  }

  Future<void> _toggleLoop() async {
    setState(() => _isLooping = !_isLooping);
    await _invoke('setLoop', {'loop': _isLooping});
    _scheduleHide();
  }

  Future<void> _toggleResizeMode() async {
    setState(() => _isCoverFit = !_isCoverFit);
    await _invoke('setResizeMode', {'mode': _isCoverFit ? 'cover' : 'fit'});
    _scheduleHide();
  }

  String _formatDuration(Duration d) {
    final totalSeconds = d.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    final ss = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      final mm = minutes.toString().padLeft(2, '0');
      return '$hours:$mm:$ss';
    }
    return '$minutes:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_error != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1B26),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: cs.error.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: cs.error, size: 42),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
              if (widget.onClose != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: widget.onClose,
                  child: const Text('Close'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!_useNative) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Text(
          'In-memory secure video playback is supported on Android.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final durationMs = _duration.inMilliseconds.toDouble();
    final positionMs = (_dragValueMs ?? _position.inMilliseconds.toDouble())
        .clamp(0.0, durationMs > 0 ? durationMs : 1.0);

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AndroidView(
            key: ValueKey('secure-video-$_viewRevision'),
            viewType: _inlineMediaViewType,
            creationParams: {
              'kind': 'video',
              'bytes': widget.bytes,
              'loop': _isLooping,
              'muted': _isMuted,
              'autoPlay': widget.autoPlay,
              'fit': _isCoverFit ? 'cover' : 'fit',
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onPlatformViewCreated,
          ),

          // Gesture layer: single tap toggles controls; double tap left/right seeks 10s.
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTap: () => _seekBy(-10),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTap: () => _seekBy(10),
                ),
              ),
            ],
          ),

          // Double-tap seek feedback badge.
          if (_seekFeedbackSeconds != null)
            Align(
              alignment: _seekFeedbackSeconds! < 0
                  ? const Alignment(-0.55, 0)
                  : const Alignment(0.55, 0),
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.16),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _seekFeedbackSeconds! < 0
                            ? Icons.replay_10_rounded
                            : Icons.forward_10_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _seekFeedbackSeconds! < 0 ? '-10s' : '+10s',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Controls overlay.
          IgnorePointer(
            ignoring: !_controlsVisible,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.65),
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.78),
                    ],
                    stops: const [0.0, 0.22, 0.72, 1.0],
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      if (widget.showTopBar)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          child: Row(
                            children: [
                              _GlassIconButton(
                                icon: Icons.arrow_back_rounded,
                                tooltip: 'Back',
                                onPressed:
                                    widget.onClose ??
                                    () => Navigator.of(context).maybePop(),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              ...widget.trailingActions,
                            ],
                          ),
                        ),
                      const Spacer(),
                      // Center transport controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _GlassIconButton(
                            icon: Icons.replay_10_rounded,
                            tooltip: 'Rewind 10 seconds',
                            size: 46,
                            iconSize: 26,
                            onPressed: () => _seekBy(-10),
                          ),
                          const SizedBox(width: 24),
                          GestureDetector(
                            onTap: _togglePlayPause,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.92),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: cs.primary.withValues(alpha: 0.4),
                                    blurRadius: 18,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: _isBuffering
                                    ? SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.6,
                                          color: cs.onPrimary,
                                        ),
                                      )
                                    : Icon(
                                        _isEnded
                                            ? Icons.replay_rounded
                                            : _isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: cs.onPrimary,
                                        size: 38,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          _GlassIconButton(
                            icon: Icons.forward_10_rounded,
                            tooltip: 'Forward 10 seconds',
                            size: 46,
                            iconSize: 26,
                            onPressed: () => _seekBy(10),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Bottom scrubber + action pills
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.54),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 16,
                                  ),
                                  activeTrackColor: cs.primary,
                                  inactiveTrackColor: Colors.white.withValues(
                                    alpha: 0.24,
                                  ),
                                  secondaryActiveTrackColor: Colors.white
                                      .withValues(alpha: 0.42),
                                  thumbColor: Colors.white,
                                ),
                                child: Slider(
                                  value: positionMs,
                                  min: 0.0,
                                  max: durationMs > 0 ? durationMs : 1.0,
                                  secondaryTrackValue:
                                      durationMs > 0
                                          ? _buffered.inMilliseconds
                                              .toDouble()
                                              .clamp(0.0, durationMs)
                                          : null,
                                  onChangeStart: (v) {
                                    _hideTimer?.cancel();
                                    setState(() {
                                      _isDragging = true;
                                      _dragValueMs = v;
                                    });
                                  },
                                  onChanged: (v) {
                                    setState(() => _dragValueMs = v);
                                  },
                                  onChangeEnd: (v) async {
                                    setState(() {
                                      _isDragging = false;
                                      _dragValueMs = null;
                                      _position = Duration(
                                        milliseconds: v.round(),
                                      );
                                    });
                                    await _invoke('seekTo', {
                                      'positionMs': v.round(),
                                    });
                                    _scheduleHide();
                                  },
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      '${_formatDuration(Duration(milliseconds: positionMs.round()))} / ${_formatDuration(_duration)}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    _ControlPill(
                                      label: '${_speeds[_speedIndex]}x',
                                      tooltip: 'Playback speed',
                                      onTap: _cycleSpeed,
                                    ),
                                    const SizedBox(width: 6),
                                    _MiniIconPill(
                                      icon: _isMuted
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                      active: _isMuted,
                                      tooltip: _isMuted ? 'Unmute' : 'Mute',
                                      onTap: _toggleMute,
                                    ),
                                    const SizedBox(width: 6),
                                    _MiniIconPill(
                                      icon: _isLooping
                                          ? Icons.repeat_one_rounded
                                          : Icons.repeat_rounded,
                                      active: _isLooping,
                                      tooltip: _isLooping
                                          ? 'Loop on'
                                          : 'Loop off',
                                      onTap: _toggleLoop,
                                    ),
                                    const SizedBox(width: 6),
                                    _MiniIconPill(
                                      icon: _isCoverFit
                                          ? Icons.fit_screen_rounded
                                          : Icons.crop_free_rounded,
                                      active: _isCoverFit,
                                      tooltip: _isCoverFit
                                          ? 'Fit screen'
                                          : 'Fill screen',
                                      onTap: _toggleResizeMode,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 40,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(size / 2),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Icon(icon, color: Colors.white, size: iconSize),
        ),
      ),
    );
  }
}

class _ControlPill extends StatelessWidget {
  const _ControlPill({
    required this.label,
    required this.tooltip,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniIconPill extends StatelessWidget {
  const _MiniIconPill({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: active
                ? cs.primary.withValues(alpha: 0.85)
                : Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: Colors.white, size: 17),
        ),
      ),
    );
  }
}
