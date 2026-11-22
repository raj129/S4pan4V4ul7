import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:photo_vault/features/chat/application/media/android_chat_secure_media_service.dart';

enum SecureAudioPlaybackStatus { idle, loading, playing, paused, ended, error }

class SecureAudioState {
  const SecureAudioState({
    this.sessionId,
    this.status = SecureAudioPlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.speed = 1.0,
    this.error,
  });

  final String? sessionId;
  final SecureAudioPlaybackStatus status;
  final Duration position;
  final Duration duration;
  final double speed;
  final String? error;

  bool get isActive =>
      sessionId != null &&
      status != SecureAudioPlaybackStatus.idle &&
      status != SecureAudioPlaybackStatus.error;

  SecureAudioState copyWith({
    String? sessionId,
    SecureAudioPlaybackStatus? status,
    Duration? position,
    Duration? duration,
    double? speed,
    String? error,
  }) => SecureAudioState(
    sessionId: sessionId ?? this.sessionId,
    status: status ?? this.status,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    speed: speed ?? this.speed,
    error: error,
  );
}

/// Coordinates single-active in-memory audio playback across Chat and Vault.
class SecureAudioController extends ChangeNotifier {
  SecureAudioController({
    AndroidChatSecureMediaService service =
        const AndroidChatSecureMediaService(),
  }) : _service = service {
    _service.setAudioStateHandler(_handleNativeEvent);
  }

  static final SecureAudioController instance = SecureAudioController();
  static const speeds = [1.0, 1.25, 1.5, 2.0];

  final AndroidChatSecureMediaService _service;
  SecureAudioState _state = const SecureAudioState();
  int _nonce = 0;

  SecureAudioState get state => _state;

  String nextSessionId(String prefix) => '$prefix-${++_nonce}';

  SecureAudioState stateFor(String sessionId) {
    if (_state.sessionId != sessionId) return const SecureAudioState();
    return _state;
  }

  Future<void> _handleNativeEvent(Map<Object?, Object?> event) async {
    final sessionId = event['sessionId'] as String?;
    final rawState = event['state'] as String?;
    if (sessionId == null || rawState == null) return;
    if (_state.sessionId != null && _state.sessionId != sessionId) return;

    final posMs = (event['positionMs'] as num?)?.toInt() ?? 0;
    final durMs = (event['durationMs'] as num?)?.toInt() ?? 0;
    final speed = (event['speed'] as num?)?.toDouble() ?? _state.speed;
    final err = event['error'] as String?;

    final status = switch (rawState) {
      'loading' => SecureAudioPlaybackStatus.loading,
      'ready' || 'paused' => SecureAudioPlaybackStatus.paused,
      'playing' => SecureAudioPlaybackStatus.playing,
      'ended' => SecureAudioPlaybackStatus.ended,
      'error' => SecureAudioPlaybackStatus.error,
      'stopped' => SecureAudioPlaybackStatus.idle,
      _ => SecureAudioPlaybackStatus.idle,
    };

    if (status == SecureAudioPlaybackStatus.idle) {
      _state = const SecureAudioState();
    } else {
      _state = SecureAudioState(
        sessionId: sessionId,
        status: status,
        position: Duration(milliseconds: posMs),
        duration: durMs > 0 ? Duration(milliseconds: durMs) : _state.duration,
        speed: speed,
        error: err,
      );
    }
    notifyListeners();
  }

  Future<void> playBytes(
    Uint8List bytes, {
    required String sessionId,
  }) async {
    AndroidChatSecureMediaService.validateBytes(bytes);
    _state = SecureAudioState(
      sessionId: sessionId,
      status: SecureAudioPlaybackStatus.loading,
    );
    notifyListeners();
    try {
      await _service.startAudio(bytes: bytes, sessionId: sessionId);
    } on PlatformException catch (e) {
      _state = SecureAudioState(
        sessionId: sessionId,
        status: SecureAudioPlaybackStatus.error,
        error: e.message ?? 'Audio unavailable.',
      );
      notifyListeners();
      rethrow;
    } catch (e) {
      _state = SecureAudioState(
        sessionId: sessionId,
        status: SecureAudioPlaybackStatus.error,
        error: 'Could not play audio.',
      );
      notifyListeners();
      rethrow;
    }
  }

  Future<void> pause(String sessionId) async {
    if (_state.sessionId != sessionId) return;
    await _service.pauseAudio(sessionId: sessionId);
  }

  Future<void> resume(String sessionId) async {
    if (_state.sessionId != sessionId) return;
    await _service.resumeAudio(sessionId: sessionId);
  }

  Future<void> seekTo(String sessionId, Duration position) async {
    if (_state.sessionId != sessionId) return;
    _state = _state.copyWith(position: position);
    notifyListeners();
    await _service.seekAudio(position: position, sessionId: sessionId);
  }

  Future<void> cycleSpeed(String sessionId) async {
    if (_state.sessionId != sessionId) return;
    final idx = speeds.indexWhere((s) => (s - _state.speed).abs() < 0.05);
    final next = speeds[(idx + 1) % speeds.length];
    _state = _state.copyWith(speed: next);
    notifyListeners();
    await _service.setAudioSpeed(speed: next, sessionId: sessionId);
  }

  Future<void> stop([String? sessionId]) async {
    if (sessionId != null && _state.sessionId != sessionId) return;
    _state = const SecureAudioState();
    notifyListeners();
    await _service.stopAudio(sessionId: sessionId);
  }
}

/// Modern Material 3 bottom sheet for standalone/Vault audio playback.
class SecureAudioPlayerSheet extends StatefulWidget {
  const SecureAudioPlayerSheet({
    super.key,
    required this.bytes,
    this.title = 'Audio',
    this.controller,
  });

  final Uint8List bytes;
  final String title;
  final SecureAudioController? controller;

  static Future<void> show(
    BuildContext context, {
    required Uint8List bytes,
    String title = 'Audio',
    SecureAudioController? controller,
  }) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => SecureAudioPlayerSheet(
      bytes: bytes,
      title: title,
      controller: controller,
    ),
  );

  @override
  State<SecureAudioPlayerSheet> createState() => _SecureAudioPlayerSheetState();
}

class _SecureAudioPlayerSheetState extends State<SecureAudioPlayerSheet> {
  late final SecureAudioController _controller;
  late final String _sessionId;
  double? _dragMs;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SecureAudioController.instance;
    _sessionId = _controller.nextSessionId('sheet');
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await _controller.playBytes(widget.bytes, sessionId: _sessionId);
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_controller.stop(_sessionId).catchError((Object _) {}));
    super.dispose();
  }

  String _fmt(Duration d) {
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
        final s = _controller.stateFor(_sessionId);
        final durMs = s.duration.inMilliseconds.toDouble();
        final posMs = (_dragMs ?? s.position.inMilliseconds.toDouble()).clamp(
          0.0,
          durMs > 0 ? durMs : 1.0,
        );
        final isPlaying = s.status == SecureAudioPlaybackStatus.playing;
        final isLoading = s.status == SecureAudioPlaybackStatus.loading;

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (s.status == SecureAudioPlaybackStatus.error)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    s.error ?? 'Could not play audio.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: cs.error),
                  ),
                )
              else ...[
                Slider(
                  value: posMs,
                  min: 0.0,
                  max: durMs > 0 ? durMs : 1.0,
                  onChangeStart: (v) => setState(() => _dragMs = v),
                  onChanged: (v) => setState(() => _dragMs = v),
                  onChangeEnd: (v) async {
                    setState(() => _dragMs = null);
                    await _controller.seekTo(
                      _sessionId,
                      Duration(milliseconds: v.round()),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(Duration(milliseconds: posMs.round())),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        s.duration > Duration.zero ? _fmt(s.duration) : '--:--',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ActionChip(
                      label: Text('${s.speed}x'),
                      onPressed: () => _controller.cycleSpeed(_sessionId),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      tooltip: 'Rewind 10s',
                      icon: const Icon(Icons.replay_10_rounded),
                      onPressed: () {
                        final target =
                            (s.position - const Duration(seconds: 10));
                        _controller.seekTo(
                          _sessionId,
                          target < Duration.zero ? Duration.zero : target,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(16),
                      ),
                      onPressed: isLoading
                          ? null
                          : () {
                              if (isPlaying) {
                                _controller.pause(_sessionId);
                              } else {
                                _controller.resume(_sessionId);
                              }
                            },
                      child: isLoading
                          ? SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: cs.onPrimary,
                              ),
                            )
                          : Icon(
                              isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 28,
                            ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Forward 10s',
                      icon: const Icon(Icons.forward_10_rounded),
                      onPressed: () {
                        final target =
                            s.position + const Duration(seconds: 10);
                        _controller.seekTo(
                          _sessionId,
                          s.duration > Duration.zero && target > s.duration
                              ? s.duration
                              : target,
                        );
                      },
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
