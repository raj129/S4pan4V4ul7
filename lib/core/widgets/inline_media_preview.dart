import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../media/animated_media.dart';
import '../platform/hdr_preview_capability.dart';
import 'animated_media_image.dart';

const _inlineMediaViewType = 'photo_vault/inline_media';

class InlineHdrImagePreview extends StatefulWidget {
  const InlineHdrImagePreview({
    required this.bytes,
    required this.fit,
    this.errorBuilder,
    super.key,
  });

  final Uint8List bytes;
  final BoxFit fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  @override
  State<InlineHdrImagePreview> createState() => _InlineHdrImagePreviewState();
}

class _InlineHdrImagePreviewState extends State<InlineHdrImagePreview>
    with WidgetsBindingObserver {
  final _preference = HdrPreviewPreference.instance;
  Uint8List? _platformBytes;
  bool _preferenceLoaded = false;
  bool _useFallback = false;
  int _viewRevision = 0;
  MethodChannel? _channel;

  bool get _useNative =>
      _preferenceLoaded &&
      _preference.enabled.value &&
      HdrPreviewCapability.instance.available.value;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preference.enabled.addListener(_onHdrPreferenceChanged);
    HdrPreviewCapability.instance.available.addListener(
      _onHdrCapabilityChanged,
    );
    unawaited(_loadHdrPreference());
    unawaited(_loadHdrCapability());
  }

  Future<void> _loadHdrPreference() async {
    try {
      await _preference.load();
    } catch (error) {
      debugPrint('Could not load HDR preview preference: $error');
      return;
    }
    if (!mounted) return;
    setState(() {
      _preferenceLoaded = true;
      if (_useNative) _copyPlatformBytes();
      _viewRevision++;
    });
  }

  Future<void> _loadHdrCapability() async {
    try {
      await HdrPreviewCapability.instance.load();
    } catch (error) {
      debugPrint('Could not determine HDR preview support: $error');
    }
  }

  @override
  void didUpdateWidget(InlineHdrImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.bytes, widget.bytes)) {
      _releasePlatformBytes();
      _useFallback = false;
      _channel = null;
      if (_useNative) _copyPlatformBytes();
      _viewRevision++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _useNative && !_useFallback) {
      _releasePlatformBytes();
      _copyPlatformBytes();
      setState(() => _viewRevision++);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preference.enabled.removeListener(_onHdrPreferenceChanged);
    HdrPreviewCapability.instance.available.removeListener(
      _onHdrCapabilityChanged,
    );
    _channel?.setMethodCallHandler(null);
    _releasePlatformBytes();
    super.dispose();
  }

  void _onHdrPreferenceChanged() {
    _refreshNativePreview();
  }

  void _onHdrCapabilityChanged() {
    _refreshNativePreview();
  }

  void _refreshNativePreview() {
    if (!mounted) return;
    setState(() {
      // A fresh native view per toggle re-applies (or restores) colour mode.
      _releasePlatformBytes();
      _channel?.setMethodCallHandler(null);
      _channel = null;
      _useFallback = false;
      if (_useNative) _copyPlatformBytes();
      _viewRevision++;
    });
  }

  void _copyPlatformBytes() {
    _platformBytes = Uint8List.fromList(widget.bytes);
  }

  void _releasePlatformBytes() {
    final bytes = _platformBytes;
    _platformBytes = null;
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_inlineMediaViewType/$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'statusChanged') {
        final arguments = call.arguments;
        if (arguments is Map &&
            (arguments['status'] == 'error' ||
                arguments['status'] == 'closed')) {
          _showFallback(arguments['message'] as String?);
        }
      }
    });
    unawaited(_readNativeStatus(channel));
  }

  Future<void> _readNativeStatus(MethodChannel channel) async {
    try {
      final status = await channel.invokeMapMethod<Object?, Object?>(
        'getStatus',
      );
      if (status?['status'] == 'error') {
        _showFallback(status?['message'] as String?);
      }
    } on PlatformException catch (error) {
      _showFallback(error.message);
    } on MissingPluginException {
      _showFallback(null);
    }
  }

  void _showFallback(String? error) {
    if (!mounted || _useFallback) return;
    setState(() {
      _useFallback = true;
      _viewRevision++;
    });
    _releasePlatformBytes();
    _channel?.setMethodCallHandler(null);
    _channel = null;
    if (error != null && error.isNotEmpty) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('HDR preview unavailable: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sdr = Image.memory(
      widget.bytes,
      fit: widget.fit,
      errorBuilder: widget.errorBuilder,
    );
    if (_useNative && !_useFallback && _platformBytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          sdr,
          // Hybrid composition draws the real native view in the window, so
          // the HDR colour mode and gainmap apply; a texture-composited
          // AndroidView renders SDR, making HDR on/off look identical.
          PlatformViewLink(
            key: ValueKey('hdr-native-view-$_viewRevision'),
            viewType: _inlineMediaViewType,
            surfaceFactory: (context, controller) => AndroidViewSurface(
              controller: controller as AndroidViewController,
              gestureRecognizers: const {},
              hitTestBehavior: PlatformViewHitTestBehavior.transparent,
            ),
            onCreatePlatformView: (params) {
              return PlatformViewsService.initExpensiveAndroidView(
                  id: params.id,
                  viewType: _inlineMediaViewType,
                  layoutDirection: TextDirection.ltr,
                  creationParams: {
                    'kind': 'hdrImage',
                    'bytes': _platformBytes,
                    'fit': widget.fit == BoxFit.cover ? 'cover' : 'contain',
                  },
                  creationParamsCodec: const StandardMessageCodec(),
                  onFocus: () => params.onFocusChanged(true),
                )
                ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
                ..addOnPlatformViewCreatedListener(_onPlatformViewCreated)
                ..create();
            },
          ),
        ],
      );
    }
    return sdr;
  }
}

class InlineMotionPhotoPreview extends StatefulWidget {
  const InlineMotionPhotoPreview({
    required this.videoBytes,
    required this.stillBytes,
    required this.fit,
    this.controlAlignment = Alignment.center,
    this.controlPadding = EdgeInsets.zero,
    super.key,
  });

  final Uint8List videoBytes;
  final Uint8List stillBytes;
  final BoxFit fit;

  /// Where the play/pause control sits over the media.
  final AlignmentGeometry controlAlignment;

  /// Inset applied around the play/pause control.
  final EdgeInsetsGeometry controlPadding;

  @override
  State<InlineMotionPhotoPreview> createState() =>
      _InlineMotionPhotoPreviewState();
}

class _InlineMotionPhotoPreviewState extends State<InlineMotionPhotoPreview>
    with WidgetsBindingObserver {
  final _preference = MediaAnimationPreference.instance;
  Uint8List? _platformBytes;
  MethodChannel? _channel;
  MediaAnimationMode _mode = MediaAnimationMode.loop;
  bool _preferenceLoaded = false;
  bool _showStill = false;
  bool _isPlaying = true;
  bool _playbackFailed = false;
  bool _pendingPause = false;
  int _viewRevision = 0;

  bool get _useNative =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _preference.mode.addListener(_onPreferenceChanged);
    unawaited(_loadPreference());
  }

  Future<void> _loadPreference() async {
    try {
      await _preference.load();
    } catch (error) {
      debugPrint('Could not load Motion Photo playback mode: $error');
    }
    if (!mounted) return;
    setState(() {
      _mode = _preference.mode.value;
      _preferenceLoaded = true;
      _preparePlatformBytes();
      _viewRevision++;
    });
  }

  @override
  void didUpdateWidget(InlineMotionPhotoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.videoBytes, widget.videoBytes) ||
        !identical(oldWidget.stillBytes, widget.stillBytes)) {
      _releasePlatformBytes();
      _showStill = false;
      _playbackFailed = false;
      if (_preferenceLoaded) _preparePlatformBytes();
      _viewRevision++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed ||
        !_useNative ||
        !_preferenceLoaded ||
        _showStill) {
      return;
    }
    _releasePlatformBytes();
    _preparePlatformBytes();
    setState(() {
      _isPlaying = true;
      _viewRevision++;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _preference.mode.removeListener(_onPreferenceChanged);
    _channel?.setMethodCallHandler(null);
    _releasePlatformBytes();
    super.dispose();
  }

  void _preparePlatformBytes() {
    _platformBytes = Uint8List.fromList(widget.videoBytes);
  }

  void _releasePlatformBytes() {
    final bytes = _platformBytes;
    _platformBytes = null;
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
  }

  void _onPreferenceChanged() {
    final next = _preference.mode.value;
    if (next == _mode) return;
    setState(() => _mode = next);
    if (_showStill && next == MediaAnimationMode.loop) {
      unawaited(_togglePlayback());
      return;
    }
    final channel = _channel;
    if (channel != null) {
      unawaited(
        channel
            .invokeMethod<void>('setLoop', {
              'loop': next == MediaAnimationMode.loop,
            })
            .catchError((Object error) {
              debugPrint('Could not update Motion Photo playback mode: $error');
            }),
      );
    }
  }

  void _onPlatformViewCreated(int viewId) {
    final channel = MethodChannel('$_inlineMediaViewType/$viewId');
    _channel = channel;
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'playingChanged') {
        setState(() => _isPlaying = call.arguments == true);
      } else if (call.method == 'ended') {
        _releasePlatformBytes();
        setState(() {
          _showStill = true;
          _isPlaying = false;
        });
        _channel?.setMethodCallHandler(null);
        _channel = null;
      } else if (call.method == 'statusChanged') {
        final arguments = call.arguments;
        if (arguments is Map && arguments['status'] == 'error') {
          _showPlaybackFallback();
        } else if (arguments is Map && arguments['status'] == 'closed') {
          _releasePlatformBytes();
          setState(() {
            _showStill = true;
            _isPlaying = false;
          });
          _channel?.setMethodCallHandler(null);
          _channel = null;
        }
      }
    });
    unawaited(_readNativeStatus(channel));
    if (_pendingPause) {
      _pendingPause = false;
      unawaited(channel.invokeMethod<void>('toggle'));
    }
  }

  Future<void> _readNativeStatus(MethodChannel channel) async {
    try {
      final status = await channel.invokeMapMethod<Object?, Object?>(
        'getStatus',
      );
      if (!mounted) return;
      if (status?['status'] == 'error') {
        _showPlaybackFallback();
      } else if (status?['status'] == 'ended') {
        setState(() {
          _showStill = true;
          _isPlaying = false;
        });
      } else if (status?['playing'] is bool) {
        setState(() => _isPlaying = status!['playing'] as bool);
      }
    } on PlatformException {
      _showPlaybackFallback();
    } on MissingPluginException {
      _showPlaybackFallback();
    }
  }

  void _showPlaybackFallback() {
    if (!mounted) return;
    _releasePlatformBytes();
    setState(() {
      _showStill = true;
      _isPlaying = false;
      _playbackFailed = true;
    });
    _channel?.setMethodCallHandler(null);
    _channel = null;
  }

  Future<void> _togglePlayback() async {
    if (_showStill || _playbackFailed) {
      // Playing from the still returns to looping until the next pause.
      unawaited(_setRememberedMode(MediaAnimationMode.loop));
      _releasePlatformBytes();
      _preparePlatformBytes();
      setState(() {
        _showStill = false;
        _playbackFailed = false;
        _isPlaying = true;
        _viewRevision++;
      });
      return;
    }
    if (_channel == null) {
      _pendingPause = false;
      _releasePlatformBytes();
      setState(() {
        _showStill = true;
        _isPlaying = false;
      });
      return;
    }
    final wasPlaying = _isPlaying;
    if (wasPlaying) {
      unawaited(_setRememberedMode(MediaAnimationMode.once));
      try {
        await _channel?.invokeMethod<void>('close');
      } catch (error) {
        debugPrint('Could not stop Motion Photo playback: $error');
      }
      _releasePlatformBytes();
      _channel?.setMethodCallHandler(null);
      _channel = null;
      if (mounted) {
        setState(() {
          _showStill = true;
          _isPlaying = false;
        });
      }
      return;
    }
    try {
      await _channel?.invokeMethod<void>('toggle');
    } on PlatformException catch (error) {
      debugPrint('Could not toggle Motion Photo playback: ${error.message}');
      _showPlaybackFallback();
    }
  }

  /// Pausing remembers play-once so the next open plays once, then shows HDR.
  Future<void> _setRememberedMode(MediaAnimationMode next) async {
    if (_preference.mode.value == next) return;
    try {
      await _preference.setMode(next);
    } catch (error) {
      debugPrint('Could not save Motion Photo playback mode: $error');
    }
  }

  Widget _stillFrame() {
    if (isHdrImage(widget.stillBytes)) {
      return InlineHdrImagePreview(bytes: widget.stillBytes, fit: widget.fit);
    }
    return AnimatedMediaImage(bytes: widget.stillBytes, fit: widget.fit);
  }

  @override
  Widget build(BuildContext context) {
    if (!_useNative) return _stillFrame();
    if (!_preferenceLoaded) return _stillFrame();

    return Stack(
      fit: StackFit.expand,
      children: [
        // The still stays underneath so the view swap never shows a blank frame.
        _stillFrame(),
        if (!(_showStill || _playbackFailed || _platformBytes == null))
          AndroidView(
            key: ValueKey(_viewRevision),
            viewType: _inlineMediaViewType,
            creationParams: {
              'kind': 'motionPhoto',
              'bytes': _platformBytes,
              'loop': _mode == MediaAnimationMode.loop,
            },
            creationParamsCodec: const StandardMessageCodec(),
            onPlatformViewCreated: _onPlatformViewCreated,
          ),
        Align(
          alignment: widget.controlAlignment,
          child: Padding(
            padding: widget.controlPadding,
            child: IconButton(
              tooltip: _isPlaying ? 'Pause motion photo' : 'Play motion photo',
              onPressed: _togglePlayback,
              color: Colors.white,
              icon: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
