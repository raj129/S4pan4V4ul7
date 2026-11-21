import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../media/animated_media.dart';

class AnimatedMediaImage extends StatefulWidget {
  const AnimatedMediaImage({
    required this.bytes,
    required this.fit,
    this.cacheWidth,
    this.cacheHeight,
    this.errorBuilder,
    this.maxLoops = 2,
    this.enablePlaybackControls = true,
    super.key,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  /// Automatically pauses animated GIFs after this many loops to save CPU and
  /// memory. Null disables auto-pausing.
  final int? maxLoops;

  /// Enables tap-to-play/pause and the bottom-right status icon for GIFs.
  final bool enablePlaybackControls;

  @override
  State<AnimatedMediaImage> createState() => _AnimatedMediaImageState();
}

class _AnimatedMediaImageState extends State<AnimatedMediaImage> {
  ui.Codec? _codec;
  ui.FrameInfo? _frame;
  Timer? _timer;
  Object? _error;
  ImageProvider? _loopProvider;
  int _frameCount = 1;
  int _frameIndex = 0;
  int _completedLoops = 0;
  bool _paused = false;
  int _generation = 0;

  bool get _useCodec =>
      MediaAnimationPreference.instance.mode.value == MediaAnimationMode.once ||
      isGif(widget.bytes);

  @override
  void initState() {
    super.initState();
    MediaAnimationPreference.instance.mode.addListener(_onModeChanged);
    // A tile built after the preference loaded gets no change event, so it
    // must decode itself or it stays blank.
    if (_useCodec) {
      unawaited(_decode());
    }
    unawaited(_loadAnimationPreference());
  }

  Future<void> _loadAnimationPreference() async {
    try {
      await MediaAnimationPreference.instance.load();
    } catch (error) {
      debugPrint('Could not load media animation preference: $error');
    }
  }

  @override
  void didUpdateWidget(AnimatedMediaImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes) ||
        oldWidget.cacheWidth != widget.cacheWidth ||
        oldWidget.cacheHeight != widget.cacheHeight) {
      final previousProvider = _loopProvider;
      _loopProvider = null;
      if (previousProvider != null) {
        unawaited(previousProvider.evict());
      }
      _paused = false;
      _completedLoops = 0;
      if (_useCodec) {
        _decode();
      }
    }
  }

  @override
  void dispose() {
    MediaAnimationPreference.instance.mode.removeListener(_onModeChanged);
    final provider = _loopProvider;
    if (provider != null) unawaited(provider.evict());
    _disposeCodec();
    _frame?.image.dispose();
    super.dispose();
  }

  void _onModeChanged() {
    _paused = false;
    _completedLoops = 0;
    if (_useCodec) {
      _decode();
      return;
    }
    _generation++;
    _disposeCodec();
    _frame?.image.dispose();
    _frame = null;
    if (mounted) setState(() {});
  }

  void _disposeCodec() {
    _timer?.cancel();
    _timer = null;
    _codec?.dispose();
    _codec = null;
  }

  Future<void> _decode({bool resetLoops = true}) async {
    final generation = ++_generation;
    _disposeCodec();
    final oldFrame = _frame;
    _frame = null;
    oldFrame?.image.dispose();
    _frameIndex = 0;
    if (resetLoops) _completedLoops = 0;
    _paused = false;
    _error = null;

    try {
      final codec = await ui.instantiateImageCodec(
        widget.bytes,
        targetWidth: widget.cacheWidth,
        targetHeight: widget.cacheHeight,
      );
      if (!mounted || generation != _generation) {
        codec.dispose();
        return;
      }
      _codec = codec;
      _frameCount = codec.frameCount;
      await _showNextFrame(generation);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  int? get _effectiveMaxLoops {
    if (MediaAnimationPreference.instance.mode.value ==
        MediaAnimationMode.once) {
      return 1;
    }
    return widget.maxLoops;
  }

  void _pausePlayback() {
    _generation++;
    _disposeCodec();
    if (mounted) {
      setState(() => _paused = true);
    }
  }

  void _togglePlayback() {
    if (_paused) {
      unawaited(_decode(resetLoops: true));
    } else {
      _pausePlayback();
    }
  }

  Future<void> _showNextFrame(int generation) async {
    final codec = _codec;
    if (codec == null || !mounted || generation != _generation) return;
    if (_frameIndex >= _frameCount) {
      _completedLoops++;
      final limit = _effectiveMaxLoops;
      if (limit != null && _completedLoops >= limit) {
        _pausePlayback();
        return;
      }
      // Restart codec for the next loop while keeping the current frame visible
      // until the first frame of the next loop is decoded.
      _disposeCodec();
      _frameIndex = 0;
      try {
        final nextCodec = await ui.instantiateImageCodec(
          widget.bytes,
          targetWidth: widget.cacheWidth,
          targetHeight: widget.cacheHeight,
        );
        if (!mounted || generation != _generation) {
          nextCodec.dispose();
          return;
        }
        _codec = nextCodec;
        _frameCount = nextCodec.frameCount;
      } catch (error) {
        if (!mounted || generation != _generation) return;
        setState(() => _error = error);
        return;
      }
    }

    try {
      final activeCodec = _codec;
      if (activeCodec == null || !mounted || generation != _generation) return;
      final frame = await activeCodec.getNextFrame();
      if (!mounted || generation != _generation) {
        frame.image.dispose();
        return;
      }
      final previous = _frame;
      setState(() {
        _frame = frame;
        _frameIndex++;
      });
      previous?.image.dispose();

      if (_frameCount > 1) {
        final limit = _effectiveMaxLoops;
        if (limit != null &&
            _frameIndex >= _frameCount &&
            _completedLoops + 1 >= limit) {
          _completedLoops++;
          _pausePlayback();
          return;
        }
        final delay = frame.duration > Duration.zero
            ? frame.duration
            : const Duration(milliseconds: 100);
        _timer = Timer(delay, () => _showNextFrame(generation));
      }
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_useCodec) {
      final image = _loopProvider ??= _createLoopProvider();
      return Image(
        image: image,
        fit: widget.fit,
        errorBuilder: widget.errorBuilder,
      );
    }
    if (_error case final error?) {
      return widget.errorBuilder?.call(context, error, null) ??
          const Icon(Icons.broken_image_outlined);
    }
    final frame = _frame;
    if (frame == null) return const SizedBox.shrink();
    final image = RawImage(
      image: frame.image,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
    );
    if (!widget.enablePlaybackControls ||
        !isGif(widget.bytes) ||
        _frameCount <= 1) {
      return image;
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayback,
      child: Stack(
        fit: StackFit.expand,
        children: [
          image,
          Positioned(
            right: 6,
            bottom: 6,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 2),
                    const Text(
                      'GIF',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  ImageProvider _createLoopProvider() {
    final memory = MemoryImage(widget.bytes);
    if (widget.cacheWidth == null && widget.cacheHeight == null) return memory;
    return ResizeImage(
      memory,
      width: widget.cacheWidth,
      height: widget.cacheHeight,
      policy: ResizeImagePolicy.fit,
    );
  }
}
