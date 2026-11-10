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
    super.key,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

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
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    MediaAnimationPreference.instance.mode.addListener(_onModeChanged);
    // A tile built after the preference loaded gets no change event, so it
    // must decode itself or it stays blank.
    if (MediaAnimationPreference.instance.mode.value ==
        MediaAnimationMode.once) {
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
      if (MediaAnimationPreference.instance.mode.value ==
          MediaAnimationMode.once) {
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
    if (MediaAnimationPreference.instance.mode.value ==
        MediaAnimationMode.once) {
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

  Future<void> _decode() async {
    final generation = ++_generation;
    _disposeCodec();
    final oldFrame = _frame;
    _frame = null;
    oldFrame?.image.dispose();
    _frameIndex = 0;
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

  Future<void> _showNextFrame(int generation) async {
    final codec = _codec;
    if (codec == null || !mounted || generation != _generation) return;
    if (_frameIndex >= _frameCount) {
      if (MediaAnimationPreference.instance.mode.value ==
          MediaAnimationMode.once) {
        return;
      }
      _disposeCodec();
      await _decode();
      return;
    }

    final frame = await codec.getNextFrame();
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

    if (_frameCount > 1 &&
        !(MediaAnimationPreference.instance.mode.value ==
                MediaAnimationMode.once &&
            _frameIndex >= _frameCount)) {
      _timer = Timer(frame.duration, () => _showNextFrame(generation));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (MediaAnimationPreference.instance.mode.value ==
        MediaAnimationMode.loop) {
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
    return RawImage(
      image: frame.image,
      fit: widget.fit,
      filterQuality: FilterQuality.medium,
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
