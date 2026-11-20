import 'dart:typed_data';
import 'dart:ui';

import '../../../application/media/image_compressor.dart';
import '../../../application/media/video_compressor.dart';

enum EditorTool { none, draw, crop, stickers }

enum EditorBrushType { marker, highlighter }

enum CropAspectPreset {
  free('Free', null),
  original('Original', null),
  square('1:1', 1.0),
  fourThree('4:3', 4.0 / 3.0),
  sixteenNine('16:9', 16.0 / 9.0);

  const CropAspectPreset(this.label, this.ratio);
  final String label;
  final double? ratio;
}

class EditorStroke {
  const EditorStroke({
    required this.points,
    required this.color,
    required this.strokeWidthNormalized,
    required this.brushType,
  });

  /// Normalized points in 0..1 of the rotated uncropped media frame.
  final List<Offset> points;
  final Color color;

  /// Stroke width as a fraction of the media's shorter display dimension.
  final double strokeWidthNormalized;
  final EditorBrushType brushType;

  EditorStroke copyWith({
    List<Offset>? points,
    Color? color,
    double? strokeWidthNormalized,
    EditorBrushType? brushType,
  }) {
    return EditorStroke(
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidthNormalized:
          strokeWidthNormalized ?? this.strokeWidthNormalized,
      brushType: brushType ?? this.brushType,
    );
  }

  /// Rotates all points 90 degrees clockwise around the unit square.
  EditorStroke rotated90Clockwise() {
    return copyWith(
      points: points
          .map((p) => Offset(1.0 - p.dy, p.dx))
          .toList(growable: false),
    );
  }
}

enum EditorStickerKind { emoji, imageBytes }

class EditorSticker {
  const EditorSticker({
    required this.id,
    required this.kind,
    required this.center,
    this.scale = 1.0,
    this.rotation = 0.0,
    this.emoji,
    this.imageBytes,
    this.label,
  });

  final String id;
  final EditorStickerKind kind;

  /// Normalized center in 0..1 of the rotated uncropped media frame.
  final Offset center;
  final double scale;
  final double rotation;
  final String? emoji;
  final Uint8List? imageBytes;
  final String? label;

  EditorSticker copyWith({
    Offset? center,
    double? scale,
    double? rotation,
  }) {
    return EditorSticker(
      id: id,
      kind: kind,
      center: center ?? this.center,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      emoji: emoji,
      imageBytes: imageBytes,
      label: label,
    );
  }

  EditorSticker rotated90Clockwise() {
    return copyWith(
      center: Offset(1.0 - center.dy, center.dx),
      rotation: rotation + (3.141592653589793 / 2.0),
    );
  }
}

class MediaEdits {
  const MediaEdits({
    this.strokes = const [],
    this.stickers = const [],
    this.cropRect = const Rect.fromLTWH(0, 0, 1, 1),
    this.rotationQuarterTurns = 0,
  });

  final List<EditorStroke> strokes;
  final List<EditorSticker> stickers;

  /// Normalized crop rect in 0..1 of the rotated media frame.
  final Rect cropRect;

  /// Clockwise 90-degree turns (0..3).
  final int rotationQuarterTurns;

  bool get isCropped =>
      cropRect.left > 0.002 ||
      cropRect.top > 0.002 ||
      cropRect.right < 0.998 ||
      cropRect.bottom < 0.998;

  bool get hasEdits =>
      strokes.isNotEmpty ||
      stickers.isNotEmpty ||
      isCropped ||
      (rotationQuarterTurns % 4) != 0;

  MediaEdits copyWith({
    List<EditorStroke>? strokes,
    List<EditorSticker>? stickers,
    Rect? cropRect,
    int? rotationQuarterTurns,
  }) {
    return MediaEdits(
      strokes: strokes ?? this.strokes,
      stickers: stickers ?? this.stickers,
      cropRect: cropRect ?? this.cropRect,
      rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
    );
  }

  MediaEdits rotated90Clockwise() {
    final rotatedCrop = Rect.fromLTRB(
      1.0 - cropRect.bottom,
      cropRect.left,
      1.0 - cropRect.top,
      cropRect.right,
    );
    return MediaEdits(
      strokes: strokes
          .map((s) => s.rotated90Clockwise())
          .toList(growable: false),
      stickers: stickers
          .map((s) => s.rotated90Clockwise())
          .toList(growable: false),
      cropRect: rotatedCrop,
      rotationQuarterTurns: (rotationQuarterTurns + 1) % 4,
    );
  }
}

class MediaEditorItem {
  MediaEditorItem({
    required this.id,
    required this.originalBytes,
    required this.isVideo,
    this.filename,
    this.sourceUri,
    this.sourceFlags = 0,
    MediaEdits? edits,
  }) : edits = edits ?? const MediaEdits();

  final String id;
  final Uint8List originalBytes;
  final bool isVideo;
  final String? filename;
  final String? sourceUri;
  final int sourceFlags;
  MediaEdits edits;
}

class MediaEditorExportedItem {
  const MediaEditorExportedItem({
    required this.id,
    required this.bytes,
    required this.isVideo,
    required this.wasEdited,
    this.filename,
    this.sourceUri,
    this.sourceFlags = 0,
  });

  final String id;
  final Uint8List bytes;
  final bool isVideo;
  final bool wasEdited;
  final String? filename;
  final String? sourceUri;
  final int sourceFlags;
}

class MediaEditorResult {
  const MediaEditorResult({
    required this.items,
    required this.imageQuality,
    required this.videoQuality,
  });

  final List<MediaEditorExportedItem> items;
  final ImageQuality imageQuality;
  final VideoQuality videoQuality;
}
