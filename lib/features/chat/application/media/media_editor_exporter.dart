import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../presentation/widgets/media_editor/media_editor_models.dart';

/// Bakes Signal-style media edits (crop, rotation, marker/highlighter strokes,
/// and stickers) into exported photo bytes or transparent video overlay PNGs.
class MediaEditorExporter {
  const MediaEditorExporter();

  static const double stickerBaseFraction = 0.24;

  static Future<ui.Image> decodeUiImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  /// Paints all strokes and stickers from [edits] onto [canvas] sized to
  /// [outputSize] (which represents the cropped & rotated media frame).
  static void paintEditsOverlay(
    Canvas canvas,
    Size outputSize,
    MediaEdits edits, {
    Map<String, ui.Image> decodedStickerImages = const {},
  }) {
    final crop = edits.cropRect;
    final cropW = crop.width <= 0 ? 1.0 : crop.width;
    final cropH = crop.height <= 0 ? 1.0 : crop.height;
    final shortSide = outputSize.shortestSide;

    Offset mapPoint(Offset normalized) => Offset(
      ((normalized.dx - crop.left) / cropW) * outputSize.width,
      ((normalized.dy - crop.top) / cropH) * outputSize.height,
    );

    // 1. Draw strokes
    for (final stroke in edits.strokes) {
      if (stroke.points.isEmpty) continue;
      final widthPx = (stroke.strokeWidthNormalized * shortSide).clamp(
        1.0,
        shortSide * 0.25,
      );
      final isHighlighter = stroke.brushType == EditorBrushType.highlighter;
      if (isHighlighter) {
        canvas.saveLayer(
          Offset.zero & outputSize,
          Paint()..color = const Color.fromRGBO(255, 255, 255, 0.45),
        );
      }

      final paint = Paint()
        ..color = stroke.color.withAlpha(255)
        ..strokeWidth = widthPx
        ..strokeCap = isHighlighter ? StrokeCap.square : StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

      if (stroke.points.length == 1) {
        final pt = mapPoint(stroke.points.first);
        canvas.drawCircle(
          pt,
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
        canvas.drawPath(path, paint);
      }

      if (isHighlighter) {
        canvas.restore();
      }
    }

    // 2. Draw stickers
    final baseStickerSize = shortSide * stickerBaseFraction;
    for (final sticker in edits.stickers) {
      final center = mapPoint(sticker.center);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(sticker.rotation);
      canvas.scale(sticker.scale);

      if (sticker.kind == EditorStickerKind.emoji && sticker.emoji != null) {
        final painter = TextPainter(
          text: TextSpan(
            text: sticker.emoji,
            style: TextStyle(fontSize: baseStickerSize * 0.82, height: 1.0),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          Offset(-painter.width / 2, -painter.height / 2),
        );
      } else if (sticker.kind == EditorStickerKind.imageBytes) {
        final img = decodedStickerImages[sticker.id];
        if (img != null) {
          final srcSize = Size(img.width.toDouble(), img.height.toDouble());
          final dstRect = Rect.fromCenter(
            center: Offset.zero,
            width: baseStickerSize,
            height: baseStickerSize,
          );
          final fitted = applyBoxFit(BoxFit.contain, srcSize, dstRect.size);
          final outRect = Alignment.center.inscribe(
            fitted.destination,
            dstRect,
          );
          final srcRect = Alignment.center.inscribe(
            fitted.source,
            Offset.zero & srcSize,
          );
          canvas.drawImageRect(
            img,
            srcRect,
            outRect,
            Paint()..filterQuality = FilterQuality.high,
          );
        }
      }

      canvas.restore();
    }
  }

  Future<Map<String, ui.Image>> _decodeStickerImages(
    List<EditorSticker> stickers,
  ) async {
    final map = <String, ui.Image>{};
    for (final s in stickers) {
      if (s.kind == EditorStickerKind.imageBytes && s.imageBytes != null) {
        try {
          map[s.id] = await decodeUiImage(s.imageBytes!);
        } catch (_) {
          // Skip unreadable sticker image
        }
      }
    }
    return map;
  }

  /// Renders [edits] onto [originalBytes] and returns PNG bytes.
  /// Returns [originalBytes] untouched if [edits.hasEdits] is false.
  Future<Uint8List> exportEditedPhoto(
    Uint8List originalBytes,
    MediaEdits edits,
  ) async {
    if (!edits.hasEdits) return originalBytes;

    final source = await decodeUiImage(originalBytes);
    final stickerImages = await _decodeStickerImages(edits.stickers);
    try {
      final turns = edits.rotationQuarterTurns % 4;
      final swap = turns % 2 == 1;
      final rotW = (swap ? source.height : source.width).toDouble();
      final rotH = (swap ? source.width : source.height).toDouble();

      final crop = edits.cropRect;
      var outW = (rotW * crop.width).round().clamp(1, 4096);
      var outH = (rotH * crop.height).round().clamp(1, 4096);

      // Keep aspect ratio if clamped
      final rawOutW = rotW * crop.width;
      final rawOutH = rotH * crop.height;
      final maxDim = math.max(rawOutW, rawOutH);
      if (maxDim > 4096) {
        final scale = 4096 / maxDim;
        outW = (rawOutW * scale).round().clamp(1, 4096);
        outH = (rawOutH * scale).round().clamp(1, 4096);
      }

      final outputSize = Size(outW.toDouble(), outH.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Offset.zero & outputSize);

      // Draw rotated & cropped source image
      canvas.save();
      canvas.scale(outW / rawOutW, outH / rawOutH);
      canvas.translate(-crop.left * rotW, -crop.top * rotH);
      canvas.translate(rotW / 2, rotH / 2);
      canvas.rotate(turns * (math.pi / 2));
      canvas.translate(-source.width / 2, -source.height / 2);
      canvas.drawImage(
        source,
        Offset.zero,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();

      // Paint strokes & stickers
      paintEditsOverlay(
        canvas,
        outputSize,
        edits,
        decodedStickerImages: stickerImages,
      );

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(outW, outH);
      picture.dispose();
      try {
        final byteData = await rendered.toByteData(
          format: ui.ImageByteFormat.png,
        );
        if (byteData == null) return originalBytes;
        return byteData.buffer.asUint8List();
      } finally {
        rendered.dispose();
      }
    } finally {
      source.dispose();
      for (final img in stickerImages.values) {
        img.dispose();
      }
    }
  }

  /// Generates a transparent PNG containing strokes & stickers for a video
  /// whose cropped rotated dimensions are [croppedSize]. Returns null if there
  /// are no strokes or stickers to burn in.
  Future<Uint8List?> exportVideoOverlayPng(
    Size croppedSize,
    MediaEdits edits,
  ) async {
    if (edits.strokes.isEmpty && edits.stickers.isEmpty) return null;

    var w = croppedSize.width;
    var h = croppedSize.height;
    if (w <= 0 || h <= 0) {
      w = 1080;
      h = 1920;
    }
    final maxDim = math.max(w, h);
    if (maxDim > 1920) {
      final scale = 1920 / maxDim;
      w *= scale;
      h *= scale;
    }
    final outW = w.round().clamp(2, 1920);
    final outH = h.round().clamp(2, 1920);
    final size = Size(outW.toDouble(), outH.toDouble());

    final stickerImages = await _decodeStickerImages(edits.stickers);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Offset.zero & size);
      paintEditsOverlay(
        canvas,
        size,
        edits,
        decodedStickerImages: stickerImages,
      );
      final picture = recorder.endRecording();
      final rendered = await picture.toImage(outW, outH);
      picture.dispose();
      try {
        final byteData = await rendered.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return byteData?.buffer.asUint8List();
      } finally {
        rendered.dispose();
      }
    } finally {
      for (final img in stickerImages.values) {
        img.dispose();
      }
    }
  }
}
