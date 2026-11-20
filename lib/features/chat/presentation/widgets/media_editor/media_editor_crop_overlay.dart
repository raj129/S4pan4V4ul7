import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'media_editor_models.dart';

enum _CropDragHandle {
  none,
  move,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  top,
  bottom,
  left,
  right,
}

/// Interactive Signal-style crop box overlay with 8 handles, aspect presets,
/// 90-degree rotation, and rule-of-thirds grid.
class MediaEditorCropOverlay extends StatefulWidget {
  const MediaEditorCropOverlay({
    super.key,
    required this.cropRect,
    required this.mediaAspectRatio,
    required this.mediaChild,
    required this.onCropRectChanged,
    required this.onRotate90,
    required this.onReset,
    required this.onDone,
    required this.onCancel,
  });

  final Rect cropRect;
  final double mediaAspectRatio;
  final Widget mediaChild;
  final ValueChanged<Rect> onCropRectChanged;
  final VoidCallback onRotate90;
  final VoidCallback onReset;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  State<MediaEditorCropOverlay> createState() => _MediaEditorCropOverlayState();
}

class _MediaEditorCropOverlayState extends State<MediaEditorCropOverlay> {
  CropAspectPreset _preset = CropAspectPreset.free;
  _CropDragHandle _activeHandle = _CropDragHandle.none;

  static const double _minFraction = 0.12;
  static const double _handleHitRadius = 26.0;

  double? get _targetDisplayAspect => switch (_preset) {
    CropAspectPreset.free => null,
    CropAspectPreset.original => widget.mediaAspectRatio,
    CropAspectPreset.square => 1.0,
    CropAspectPreset.fourThree => 4.0 / 3.0,
    CropAspectPreset.sixteenNine => 16.0 / 9.0,
  };

  void _applyPreset(CropAspectPreset preset) {
    setState(() => _preset = preset);
    final ratio = switch (preset) {
      CropAspectPreset.free => null,
      CropAspectPreset.original => widget.mediaAspectRatio,
      _ => preset.ratio,
    };
    if (ratio == null) return;

    // Fit centered rect with target aspect ratio inside current crop or unit square.
    final normalizedRatio = ratio / widget.mediaAspectRatio;
    double w = 1.0;
    double h = w / normalizedRatio;
    if (h > 1.0) {
      h = 1.0;
      w = h * normalizedRatio;
    }
    final left = (1.0 - w) / 2;
    final top = (1.0 - h) / 2;
    widget.onCropRectChanged(Rect.fromLTWH(left, top, w, h));
  }

  _CropDragHandle _hitTestHandle(Offset localPos, Size size) {
    final rect = Rect.fromLTRB(
      widget.cropRect.left * size.width,
      widget.cropRect.top * size.height,
      widget.cropRect.right * size.width,
      widget.cropRect.bottom * size.height,
    );

    bool near(Offset a, Offset b) => (a - b).distance <= _handleHitRadius;

    if (near(localPos, rect.topLeft)) return _CropDragHandle.topLeft;
    if (near(localPos, rect.topRight)) return _CropDragHandle.topRight;
    if (near(localPos, rect.bottomLeft)) return _CropDragHandle.bottomLeft;
    if (near(localPos, rect.bottomRight)) return _CropDragHandle.bottomRight;

    if ((localPos.dy - rect.top).abs() <= _handleHitRadius &&
        localPos.dx >= rect.left &&
        localPos.dx <= rect.right) {
      return _CropDragHandle.top;
    }
    if ((localPos.dy - rect.bottom).abs() <= _handleHitRadius &&
        localPos.dx >= rect.left &&
        localPos.dx <= rect.right) {
      return _CropDragHandle.bottom;
    }
    if ((localPos.dx - rect.left).abs() <= _handleHitRadius &&
        localPos.dy >= rect.top &&
        localPos.dy <= rect.bottom) {
      return _CropDragHandle.left;
    }
    if ((localPos.dx - rect.right).abs() <= _handleHitRadius &&
        localPos.dy >= rect.top &&
        localPos.dy <= rect.bottom) {
      return _CropDragHandle.right;
    }
    if (rect.contains(localPos)) return _CropDragHandle.move;
    return _CropDragHandle.none;
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (_activeHandle == _CropDragHandle.none ||
        size.width <= 0 ||
        size.height <= 0) {
      return;
    }
    final dx = details.delta.dx / size.width;
    final dy = details.delta.dy / size.height;
    var r = widget.cropRect;

    if (_activeHandle == _CropDragHandle.move) {
      final newLeft = (r.left + dx).clamp(0.0, 1.0 - r.width);
      final newTop = (r.top + dy).clamp(0.0, 1.0 - r.height);
      widget.onCropRectChanged(
        Rect.fromLTWH(newLeft, newTop, r.width, r.height),
      );
      return;
    }

    var left = r.left;
    var top = r.top;
    var right = r.right;
    var bottom = r.bottom;

    switch (_activeHandle) {
      case _CropDragHandle.topLeft:
        left = (left + dx).clamp(0.0, right - _minFraction);
        top = (top + dy).clamp(0.0, bottom - _minFraction);
      case _CropDragHandle.topRight:
        right = (right + dx).clamp(left + _minFraction, 1.0);
        top = (top + dy).clamp(0.0, bottom - _minFraction);
      case _CropDragHandle.bottomLeft:
        left = (left + dx).clamp(0.0, right - _minFraction);
        bottom = (bottom + dy).clamp(top + _minFraction, 1.0);
      case _CropDragHandle.bottomRight:
        right = (right + dx).clamp(left + _minFraction, 1.0);
        bottom = (bottom + dy).clamp(top + _minFraction, 1.0);
      case _CropDragHandle.top:
        top = (top + dy).clamp(0.0, bottom - _minFraction);
      case _CropDragHandle.bottom:
        bottom = (bottom + dy).clamp(top + _minFraction, 1.0);
      case _CropDragHandle.left:
        left = (left + dx).clamp(0.0, right - _minFraction);
      case _CropDragHandle.right:
        right = (right + dx).clamp(left + _minFraction, 1.0);
      case _CropDragHandle.move:
      case _CropDragHandle.none:
        break;
    }

    final targetRatio = _targetDisplayAspect;
    if (targetRatio != null) {
      final normRatio = targetRatio / widget.mediaAspectRatio;
      var w = right - left;
      var h = w / normRatio;
      if (top + h > 1.0) {
        h = 1.0 - top;
        w = h * normRatio;
      }
      if (left + w > 1.0) {
        w = 1.0 - left;
        h = w / normRatio;
      }
      if (w >= _minFraction && h >= _minFraction) {
        right = left + w;
        bottom = top + h;
      }
    }

    widget.onCropRectChanged(Rect.fromLTRB(left, top, right, bottom));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxW = constraints.maxWidth;
              final maxH = constraints.maxHeight;
              double stageW = maxW;
              double stageH = stageW / widget.mediaAspectRatio;
              if (stageH > maxH) {
                stageH = maxH;
                stageW = stageH * widget.mediaAspectRatio;
              }
              final size = Size(
                math.max(1.0, stageW),
                math.max(1.0, stageH),
              );
              return Center(
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      widget.mediaChild,
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (d) {
                          _activeHandle = _hitTestHandle(d.localPosition, size);
                        },
                        onPanUpdate: (d) => _onPanUpdate(d, size),
                        onPanEnd: (_) => _activeHandle = _CropDragHandle.none,
                        onPanCancel: () =>
                            _activeHandle = _CropDragHandle.none,
                        child: CustomPaint(
                          size: size,
                          painter: _CropBoxPainter(cropRect: widget.cropRect),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        // Bottom crop controls
        Container(
          color: Colors.black87,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final preset in CropAspectPreset.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(preset.label),
                          selected: _preset == preset,
                          onSelected: (_) => _applyPreset(preset),
                          selectedColor: Colors.white,
                          backgroundColor: Colors.white12,
                          labelStyle: TextStyle(
                            color: _preset == preset
                                ? Colors.black
                                : Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          side: BorderSide.none,
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: widget.onCancel,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Rotate 90°',
                        onPressed: widget.onRotate90,
                        icon: const Icon(
                          Icons.rotate_90_degrees_cw,
                          color: Colors.white,
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _preset = CropAspectPreset.free);
                          widget.onReset();
                        },
                        child: const Text(
                          'Reset',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  FilledButton(
                    onPressed: widget.onDone,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CropBoxPainter extends CustomPainter {
  const _CropBoxPainter({required this.cropRect});

  final Rect cropRect;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      cropRect.left * size.width,
      cropRect.top * size.height,
      cropRect.right * size.width,
      cropRect.bottom * size.height,
    );

    // Dimmed exterior using evenOdd path
    final scrimPath = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(scrimPath, Paint()..color = Colors.black54);

    // Outer white border
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    // Rule-of-thirds grid
    final gridPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 0.8;
    for (var i = 1; i <= 2; i++) {
      final x = rect.left + rect.width * (i / 3);
      final y = rect.top + rect.height * (i / 3);
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), gridPaint);
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), gridPaint);
    }

    // Thick L-shaped corner brackets
    final bracketLen = math.min(20.0, math.min(rect.width, rect.height) * 0.35);
    final bracketPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.square;

    // Top-left
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(bracketLen, 0),
      bracketPaint,
    );
    canvas.drawLine(
      rect.topLeft,
      rect.topLeft + Offset(0, bracketLen),
      bracketPaint,
    );
    // Top-right
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(-bracketLen, 0),
      bracketPaint,
    );
    canvas.drawLine(
      rect.topRight,
      rect.topRight + Offset(0, bracketLen),
      bracketPaint,
    );
    // Bottom-left
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(bracketLen, 0),
      bracketPaint,
    );
    canvas.drawLine(
      rect.bottomLeft,
      rect.bottomLeft + Offset(0, -bracketLen),
      bracketPaint,
    );
    // Bottom-right
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(-bracketLen, 0),
      bracketPaint,
    );
    canvas.drawLine(
      rect.bottomRight,
      rect.bottomRight + Offset(0, -bracketLen),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _CropBoxPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect;
  }
}
