import 'package:flutter/material.dart';

import 'media_editor_models.dart';

/// Paints committed and active marker/highlighter strokes onto the media frame.
class MediaStrokesPainter extends CustomPainter {
  const MediaStrokesPainter({
    required this.strokes,
    required this.cropRect,
    this.activeStroke,
  });

  final List<EditorStroke> strokes;
  final Rect cropRect;
  final EditorStroke? activeStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final all = activeStroke == null ? strokes : [...strokes, activeStroke!];
    final cropW = cropRect.width <= 0 ? 1.0 : cropRect.width;
    final cropH = cropRect.height <= 0 ? 1.0 : cropRect.height;
    final shortSide = size.shortestSide;

    Offset mapPoint(Offset p) => Offset(
      ((p.dx - cropRect.left) / cropW) * size.width,
      ((p.dy - cropRect.top) / cropH) * size.height,
    );

    canvas.save();
    canvas.clipRect(Offset.zero & size);

    for (final stroke in all) {
      if (stroke.points.isEmpty) continue;
      final widthPx = (stroke.strokeWidthNormalized * shortSide).clamp(
        1.5,
        shortSide * 0.25,
      );
      final isHighlighter = stroke.brushType == EditorBrushType.highlighter;

      if (isHighlighter) {
        canvas.saveLayer(
          Offset.zero & size,
          Paint()..color = const Color.fromRGBO(255, 255, 255, 0.45),
        );
      }

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          mapPoint(stroke.points.first),
          widthPx / 2,
          Paint()
            ..color = stroke.color.withAlpha(255)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true,
        );
      } else {
        final path = Path();
        final first = mapPoint(stroke.points.first);
        path.moveTo(first.dx, first.dy);
        for (var i = 1; i < stroke.points.length; i++) {
          final prev = mapPoint(stroke.points[i - 1]);
          final curr = mapPoint(stroke.points[i]);
          final mid = Offset((prev.dx + curr.dx) / 2, (prev.dy + curr.dy) / 2);
          path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
        }
        final last = mapPoint(stroke.points.last);
        path.lineTo(last.dx, last.dy);

        canvas.drawPath(
          path,
          Paint()
            ..color = stroke.color.withAlpha(255)
            ..strokeWidth = widthPx
            ..strokeCap = isHighlighter ? StrokeCap.square : StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke
            ..isAntiAlias = true,
        );
      }

      if (isHighlighter) {
        canvas.restore();
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant MediaStrokesPainter oldDelegate) {
    return oldDelegate.strokes != strokes ||
        oldDelegate.activeStroke != activeStroke ||
        oldDelegate.cropRect != cropRect;
  }
}

/// Signal-style vertical hue + white/black color bar with a floating preview dot.
class SignalColorSlider extends StatefulWidget {
  const SignalColorSlider({
    super.key,
    required this.color,
    required this.onChanged,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  static const List<Color> _stops = [
    Color(0xFFFFFFFF),
    Color(0xFFFF3B30),
    Color(0xFFFF9500),
    Color(0xFFFFCC00),
    Color(0xFF34C759),
    Color(0xFF00C7BE),
    Color(0xFF007AFF),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
    Color(0xFF000000),
  ];

  @override
  State<SignalColorSlider> createState() => _SignalColorSliderState();
}

class _SignalColorSliderState extends State<SignalColorSlider> {
  double _fraction = 0.12;
  bool _dragging = false;

  static const double _barHeight = 200;

  @override
  void initState() {
    super.initState();
    _fraction = _nearestFraction(widget.color);
  }

  double _nearestFraction(Color target) {
    var bestFrac = 0.12;
    var bestDist = double.infinity;
    const steps = 40;
    for (var i = 0; i <= steps; i++) {
      final f = i / steps;
      final c = _colorAt(f);
      final dr = ((c.r * 255) - (target.r * 255)).abs();
      final dg = ((c.g * 255) - (target.g * 255)).abs();
      final db = ((c.b * 255) - (target.b * 255)).abs();
      final dist = dr + dg + db;
      if (dist < bestDist) {
        bestDist = dist;
        bestFrac = f;
      }
    }
    return bestFrac;
  }

  static Color _colorAt(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final scaled = clamped * (SignalColorSlider._stops.length - 1);
    final idx = scaled.floor().clamp(0, SignalColorSlider._stops.length - 2);
    final localT = scaled - idx;
    return Color.lerp(
      SignalColorSlider._stops[idx],
      SignalColorSlider._stops[idx + 1],
      localT,
    )!;
  }

  void _updateFromDy(double dy) {
    final f = (dy / _barHeight).clamp(0.0, 1.0);
    setState(() => _fraction = f);
    widget.onChanged(_colorAt(f));
  }

  @override
  Widget build(BuildContext context) {
    final thumbTop = _fraction * (_barHeight - 16);
    return SizedBox(
      width: 64,
      height: _barHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          if (_dragging)
            Positioned(
              right: 40,
              top: (thumbTop - 8).clamp(0.0, _barHeight - 32),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: const [
                    BoxShadow(color: Colors.black54, blurRadius: 8),
                  ],
                ),
              ),
            ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (d) {
              setState(() => _dragging = true);
              _updateFromDy(d.localPosition.dy);
            },
            onVerticalDragUpdate: (d) => _updateFromDy(d.localPosition.dy),
            onVerticalDragEnd: (_) => setState(() => _dragging = false),
            onVerticalDragCancel: () => setState(() => _dragging = false),
            onTapDown: (d) => _updateFromDy(d.localPosition.dy),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 10,
                    height: _barHeight,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white70, width: 1.5),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: SignalColorSlider._stops,
                      ),
                    ),
                  ),
                  Positioned(
                    top: thumbTop,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: const [
                          BoxShadow(color: Colors.black45, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Signal-style brush/dot thickness slider with a live scaled dot preview.
class SignalDotSizeSlider extends StatefulWidget {
  const SignalDotSizeSlider({
    super.key,
    required this.value,
    required this.color,
    required this.isHighlighter,
    required this.onChanged,
  });

  /// Normalized brush width (e.g. 0.008 .. 0.08).
  final double value;
  final Color color;
  final bool isHighlighter;
  final ValueChanged<double> onChanged;

  static const double minSize = 0.008;
  static const double maxSize = 0.08;

  @override
  State<SignalDotSizeSlider> createState() => _SignalDotSizeSliderState();
}

class _SignalDotSizeSliderState extends State<SignalDotSizeSlider> {
  bool _dragging = false;

  double get _normalized =>
      ((widget.value - SignalDotSizeSlider.minSize) /
              (SignalDotSizeSlider.maxSize - SignalDotSizeSlider.minSize))
          .clamp(0.0, 1.0);

  double _previewDiameter(double norm) => 6.0 + norm * 28.0;

  @override
  Widget build(BuildContext context) {
    final norm = _normalized;
    final dotDiameter = _previewDiameter(norm);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Live dot preview badge
        AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _dragging ? Colors.black87 : Colors.black54,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Container(
            width: dotDiameter,
            height: dotDiameter,
            decoration: BoxDecoration(
              color: widget.isHighlighter
                  ? widget.color.withValues(alpha: 0.45)
                  : widget.color,
              shape: widget.isHighlighter
                  ? BoxShape.rectangle
                  : BoxShape.circle,
              borderRadius: widget.isHighlighter
                  ? BorderRadius.circular(3)
                  : null,
              border: Border.all(color: Colors.white70, width: 1),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 150,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white30,
              thumbColor: Colors.white,
            ),
            child: Slider(
              min: SignalDotSizeSlider.minSize,
              max: SignalDotSizeSlider.maxSize,
              value: widget.value.clamp(
                SignalDotSizeSlider.minSize,
                SignalDotSizeSlider.maxSize,
              ),
              onChangeStart: (_) => setState(() => _dragging = true),
              onChangeEnd: (_) => setState(() => _dragging = false),
              onChanged: widget.onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact Signal-style toggle between Marker (opaque) and Highlighter (translucent).
class SignalBrushTypeToggle extends StatelessWidget {
  const SignalBrushTypeToggle({
    super.key,
    required this.brushType,
    required this.onChanged,
  });

  final EditorBrushType brushType;
  final ValueChanged<EditorBrushType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BrushChip(
            icon: Icons.edit,
            label: 'Marker',
            selected: brushType == EditorBrushType.marker,
            onTap: () => onChanged(EditorBrushType.marker),
          ),
          _BrushChip(
            icon: Icons.border_color,
            label: 'Highlighter',
            selected: brushType == EditorBrushType.highlighter,
            onTap: () => onChanged(EditorBrushType.highlighter),
          ),
        ],
      ),
    );
  }
}

class _BrushChip extends StatelessWidget {
  const _BrushChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.black : Colors.white),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.black : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
