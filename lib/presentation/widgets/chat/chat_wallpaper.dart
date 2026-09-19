import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/chat_theme.dart';

/// Subtle patterned backdrop behind the message list.
///
/// Drawn rather than shipped as an image asset so it re-tints for light and
/// dark automatically and costs nothing to download.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final chat = context.chatColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            chat.wallpaper,
            Color.alphaBlend(
              chat.wallpaperPattern.withValues(alpha: 0.04),
              chat.wallpaper,
            ),
          ],
        ),
      ),
      child: CustomPaint(
        painter: _WallpaperPainter(color: chat.wallpaperPattern),
        child: child,
      ),
    );
  }
}

/// Scatters a sparse, repeating set of small glyphs across the canvas.
class _WallpaperPainter extends CustomPainter {
  _WallpaperPainter({required this.color});

  final Color color;

  static const _tile = 112.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;

    final cols = (size.width / _tile).ceil() + 1;
    final rows = (size.height / _tile).ceil() + 1;

    for (var row = 0; row < rows; row++) {
      for (var col = 0; col < cols; col++) {
        // Offset alternate rows so the grid does not read as a grid.
        final dx = col * _tile + (row.isEven ? 0 : _tile / 2);
        final dy = row * _tile;
        final variant = (row * 3 + col) % 4;

        canvas.save();
        canvas.translate(dx, dy);
        // Deterministic per-tile rotation keeps it organic without randomness
        // changing every repaint.
        canvas.rotate(((row * 7 + col * 5) % 8) * math.pi / 16);
        _drawGlyph(canvas, paint, variant);
        canvas.restore();
      }
    }
  }

  void _drawGlyph(Canvas canvas, Paint paint, int variant) {
    switch (variant) {
      case 0:
        // Chat bubble outline.
        final rect = RRect.fromRectAndRadius(
          const Rect.fromLTWH(0, 0, 22, 16),
          const Radius.circular(6),
        );
        canvas
          ..drawRRect(rect, paint)
          ..drawLine(const Offset(6, 16), const Offset(4, 21), paint);
      case 1:
        // Padlock, nodding at the encrypted transport.
        canvas
          ..drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(0, 8, 16, 12),
              const Radius.circular(3),
            ),
            paint,
          )
          ..drawArc(
            const Rect.fromLTWH(3.5, 2, 9, 12),
            math.pi,
            math.pi,
            false,
            paint,
          );
      case 2:
        canvas.drawCircle(Offset.zero, 6, paint);
      case 3:
        canvas
          ..drawLine(const Offset(-6, 0), const Offset(6, 0), paint)
          ..drawLine(const Offset(0, -6), const Offset(0, 6), paint);
    }
  }

  @override
  bool shouldRepaint(_WallpaperPainter oldDelegate) =>
      oldDelegate.color != color;
}
