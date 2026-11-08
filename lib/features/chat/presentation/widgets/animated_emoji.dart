import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:lottie/lottie.dart';

/// Lookup of the bundled Noto Animated Emoji (see assets/animated_emoji/).
class AnimatedEmojiRegistry {
  AnimatedEmojiRegistry._();

  static const assetDir = 'assets/animated_emoji';

  /// FE0F-stripped codepoint key -> asset file name (without extension).
  static Map<String, String>? _index;
  static Future<void>? _loading;

  static bool get isLoaded => _index != null;

  /// Loads the index once; safe to call repeatedly. A failed load is not
  /// cached, so the next caller retries instead of every emoji staying static
  /// for the rest of the session.
  static Future<void> ensureLoaded([AssetBundle? bundle]) {
    return _loading ??= () async {
      try {
        final raw = await (bundle ?? rootBundle).loadString(
          '$assetDir/index.json',
        );
        _index = buildIndex((jsonDecode(raw) as List).cast<String>());
      } catch (e) {
        debugPrint('AnimatedEmoji: index load failed: $e');
        _loading = null;
      }
    }();
  }

  @visibleForTesting
  static void debugSetIndex(Iterable<String> codepoints) {
    _index = buildIndex(codepoints);
    _loading = Future.value();
  }

  @visibleForTesting
  static void debugReset() {
    _index = null;
    _loading = null;
  }

  static Map<String, String> buildIndex(Iterable<String> codepoints) => {
    for (final cp in codepoints) _normalize(cp): cp,
  };

  /// `1f44d_1f3fd` style key for a single grapheme, as used by Noto.
  static String codepointKey(String grapheme) =>
      grapheme.runes.map((r) => r.toRadixString(16)).join('_');

  /// Asset path of the animation for [grapheme], or null if there is none.
  ///
  /// Variation selector 16 (FE0F) is ignored on both sides, because keyboards
  /// are inconsistent about emitting it (❤ vs ❤️).
  static String? assetFor(String grapheme) {
    final key = codepointKey(grapheme);
    final index = _index;
    if (index == null) {
      // Index unavailable: try the file directly; Lottie's errorBuilder
      // falls back to static text if it does not exist.
      return '$assetDir/$key.json';
    }
    final file = index[_normalize(key)];
    return file == null ? null : '$assetDir/$file.json';
  }

  static String _normalize(String key) =>
      key.split('_').where((p) => p != 'fe0f').join('_');
}

/// Renders emoji-only text with Google's animated emoji.
///
/// Each message animates once per app session the first time it is shown
/// (so scrolling back does not replay everything) and replays on tap.
/// Google only animates ~880 emoji; the rest (e.g. 🐱, 🐰) are drawn with the
/// platform's colour emoji and given a short bounce so they still move.
class AnimatedEmojiText extends StatefulWidget {
  const AnimatedEmojiText({
    super.key,
    required this.text,
    required this.playbackId,
    this.size = 48,
    this.onLongPress,
  });

  final String text;

  /// Identifies the message so autoplay happens only once per session.
  final String playbackId;
  final double size;
  final VoidCallback? onLongPress;

  static const bounceDuration = Duration(milliseconds: 900);
  static const staticEmojiDelay = Duration(milliseconds: 400);

  static final Set<String> _played = <String>{};

  @visibleForTesting
  static void debugResetPlayback() => _played.clear();

  static double _sizeForEmojiCount(double baseSize, int count) {
    final size = count >= 2 && count <= 4
        ? baseSize + 16
        : count > 0
        ? baseSize + 8
        : baseSize;
    return size * 1.2;
  }

  @override
  State<AnimatedEmojiText> createState() => _AnimatedEmojiTextState();
}

class _AnimatedEmojiTextState extends State<AnimatedEmojiText>
    with TickerProviderStateMixin {
  final Map<int, AnimationController> _controllers = {};
  final Map<int, Timer> _staticEmojiTimers = {};
  final Set<int> _animatedOnce = {};
  final Set<int> _showStaticEmoji = {};
  late bool _autoplay;

  @override
  void initState() {
    super.initState();
    _autoplay = AnimatedEmojiText._played.add(widget.playbackId);
    if (!AnimatedEmojiRegistry.isLoaded) {
      AnimatedEmojiRegistry.ensureLoaded().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final timer in _staticEmojiTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }

  AnimationController _controllerFor(int index) =>
      _controllers.putIfAbsent(index, () {
        final controller = AnimationController(vsync: this);
        controller.addStatusListener((status) {
          if (status == AnimationStatus.forward ||
              status == AnimationStatus.reverse) {
            _staticEmojiTimers.remove(index)?.cancel();
            _showStaticEmoji.remove(index);
            _animatedOnce.add(index);
          } else if (status == AnimationStatus.completed) {
            if (!_animatedOnce.contains(index)) {
              _showStaticEmoji.add(index);
              return;
            }
            _staticEmojiTimers[index]?.cancel();
            _staticEmojiTimers[index] = Timer(
              AnimatedEmojiText.staticEmojiDelay,
              () {
                if (!mounted) return;
                setState(() => _showStaticEmoji.add(index));
              },
            );
          }
        });
        return controller;
      });

  /// Gives [controller] a fixed duration for the bounce fallback and starts it
  /// if this message is autoplaying. Deferred to after the frame because it
  /// may be reached from build (including Lottie's errorBuilder).
  void _startBounce(AnimationController controller) {
    if (controller.duration != null) return;
    controller.duration = AnimatedEmojiText.bounceDuration;
    if (!_autoplay) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.forward(from: 0);
    });
  }

  void _replay() {
    for (final c in _controllers.values) {
      if (c.duration != null) c.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final graphemes = widget.text.characters
        .where((g) => g.trim().isNotEmpty)
        .toList();
    final emojiSize = AnimatedEmojiText._sizeForEmojiCount(
      widget.size,
      graphemes.length,
    );
    final fallbackStyle = TextStyle(fontSize: emojiSize * 0.92, height: 1.1);

    return Semantics(
      label: widget.text,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _replay,
        onLongPress: widget.onLongPress,
        child: Wrap(
          spacing: 2,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var i = 0; i < graphemes.length; i++)
              _buildGrapheme(i, graphemes[i], fallbackStyle, emojiSize),
          ],
        ),
      ),
    );
  }

  Widget _bounce(
    AnimationController controller,
    String grapheme,
    TextStyle style,
  ) {
    _startBounce(controller);
    return _BouncingEmoji(
      animation: controller,
      child: Text(grapheme, style: style),
    );
  }

  Widget _staticEmoji(String grapheme, TextStyle style) => FittedBox(
    fit: BoxFit.contain,
    alignment: Alignment.center,
    child: Text(grapheme, style: style),
  );

  Widget _buildGrapheme(
    int index,
    String grapheme,
    TextStyle fallbackStyle,
    double emojiSize,
  ) {
    final controller = _controllerFor(index);
    final asset = AnimatedEmojiRegistry.assetFor(grapheme);
    if (asset == null) return _bounce(controller, grapheme, fallbackStyle);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final isPlaying =
            controller.status == AnimationStatus.forward ||
            controller.status == AnimationStatus.reverse ||
            (controller.status == AnimationStatus.completed &&
                !_showStaticEmoji.contains(index));
        return SizedBox.square(
          key: ValueKey('emoji-box-$index'),
          dimension: emojiSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (!isPlaying) _staticEmoji(grapheme, fallbackStyle),
              Opacity(
                key: ValueKey('emoji-animation-$index'),
                opacity: isPlaying ? 1 : 0,
                child: child,
              ),
            ],
          ),
        );
      },
      child: Lottie.asset(
        asset,
        controller: controller,
        width: emojiSize,
        height: emojiSize,
        fit: BoxFit.contain,
        onLoaded: (composition) {
          controller.duration = composition.duration;
          if (_autoplay) {
            controller.forward(from: 0);
          } else {
            controller.value = 1;
          }
        },
        errorBuilder: (context, error, stack) {
          debugPrint('AnimatedEmoji: failed to load $asset: $error');
          return _bounce(controller, grapheme, fallbackStyle);
        },
      ),
    );
  }
}

/// A quick pop-and-wiggle for emoji that have no Lottie animation.
class _BouncingEmoji extends StatelessWidget {
  const _BouncingEmoji({required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  static final _scale = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.92), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.08), weight: 25),
    TweenSequenceItem(tween: Tween(begin: 1.08, end: 1), weight: 25),
  ]).chain(CurveTween(curve: Curves.easeInOut));

  static final _angle = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0, end: -0.18), weight: 20),
    TweenSequenceItem(tween: Tween(begin: -0.18, end: 0.18), weight: 30),
    TweenSequenceItem(tween: Tween(begin: 0.18, end: -0.08), weight: 25),
    TweenSequenceItem(tween: Tween(begin: -0.08, end: 0), weight: 25),
  ]);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => Transform.rotate(
        angle: _angle.evaluate(animation),
        child: Transform.scale(scale: _scale.evaluate(animation), child: child),
      ),
    );
  }
}
