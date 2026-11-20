import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/features/chat/application/media/image_compressor.dart';
import 'package:photo_vault/features/chat/application/media/media_editor_exporter.dart';
import 'package:photo_vault/features/chat/application/media/video_compressor.dart';
import 'package:photo_vault/features/chat/presentation/screens/chat_media_editor_screen.dart';
import 'package:photo_vault/features/chat/presentation/widgets/media_editor/media_editor_draw_controls.dart';
import 'package:photo_vault/features/chat/presentation/widgets/media_editor/media_editor_models.dart';

Uint8List _makePng(int width, int height, {int r = 40, int g = 120, int b = 220}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgba8(r, g, b, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void main() {
  group('MediaEdits', () {
    test('hasEdits is false by default and true for any edit', () {
      const clean = MediaEdits();
      expect(clean.hasEdits, isFalse);
      expect(clean.isCropped, isFalse);

      final withStroke = clean.copyWith(
        strokes: const [
          EditorStroke(
            points: [Offset(0.1, 0.1), Offset(0.5, 0.5)],
            color: Colors.red,
            strokeWidthNormalized: 0.02,
            brushType: EditorBrushType.marker,
          ),
        ],
      );
      expect(withStroke.hasEdits, isTrue);

      final withCrop = clean.copyWith(
        cropRect: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      );
      expect(withCrop.isCropped, isTrue);
      expect(withCrop.hasEdits, isTrue);

      final withRotation = clean.copyWith(rotationQuarterTurns: 1);
      expect(withRotation.hasEdits, isTrue);
    });

    test('rotated90Clockwise rotates cropRect, strokes, and stickers', () {
      const edits = MediaEdits(
        cropRect: Rect.fromLTRB(0.0, 0.0, 0.5, 1.0),
        strokes: [
          EditorStroke(
            points: [Offset(0.2, 0.1)],
            color: Colors.white,
            strokeWidthNormalized: 0.02,
            brushType: EditorBrushType.marker,
          ),
        ],
        stickers: [
          EditorSticker(
            id: 's1',
            kind: EditorStickerKind.emoji,
            center: Offset(0.2, 0.1),
            emoji: '🔥',
          ),
        ],
      );

      final rotated = edits.rotated90Clockwise();
      expect(rotated.rotationQuarterTurns, 1);
      expect(rotated.cropRect.left, closeTo(0.0, 1e-6));
      expect(rotated.cropRect.top, closeTo(0.0, 1e-6));
      expect(rotated.cropRect.right, closeTo(1.0, 1e-6));
      expect(rotated.cropRect.bottom, closeTo(0.5, 1e-6));
      expect(rotated.strokes.first.points.first.dx, closeTo(0.9, 1e-6));
      expect(rotated.strokes.first.points.first.dy, closeTo(0.2, 1e-6));
      expect(rotated.stickers.first.center.dx, closeTo(0.9, 1e-6));
      expect(rotated.stickers.first.center.dy, closeTo(0.2, 1e-6));
    });
  });

  group('MediaEditorExporter', () {
    const exporter = MediaEditorExporter();

    test('exportEditedPhoto returns original bytes when unedited', () async {
      final raw = _makePng(120, 80);
      final out = await exporter.exportEditedPhoto(raw, const MediaEdits());
      expect(identical(out, raw), isTrue);
    });

    test('exportEditedPhoto bakes crop, rotation, strokes, and emoji sticker', () async {
      final raw = _makePng(200, 100);
      const edits = MediaEdits(
        rotationQuarterTurns: 1, // now 100x200
        cropRect: Rect.fromLTRB(0.0, 0.0, 0.5, 0.5), // 50x100
        strokes: [
          EditorStroke(
            points: [Offset(0.1, 0.1), Offset(0.4, 0.4)],
            color: Colors.red,
            strokeWidthNormalized: 0.04,
            brushType: EditorBrushType.marker,
          ),
          EditorStroke(
            points: [Offset(0.1, 0.2), Offset(0.4, 0.2)],
            color: Colors.yellow,
            strokeWidthNormalized: 0.06,
            brushType: EditorBrushType.highlighter,
          ),
        ],
        stickers: [
          EditorSticker(
            id: 'e1',
            kind: EditorStickerKind.emoji,
            center: Offset(0.25, 0.25),
            emoji: '⭐',
          ),
        ],
      );

      final out = await exporter.exportEditedPhoto(raw, edits);
      final codec = await ui.instantiateImageCodec(out);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 50);
      expect(frame.image.height, 100);
      frame.image.dispose();
      codec.dispose();
    });

    test('exportVideoOverlayPng returns null without overlays and PNG with strokes', () async {
      final none = await exporter.exportVideoOverlayPng(
        const Size(720, 1280),
        const MediaEdits(cropRect: Rect.fromLTRB(0.1, 0.1, 0.9, 0.9)),
      );
      expect(none, isNull);

      final png = await exporter.exportVideoOverlayPng(
        const Size(720, 1280),
        const MediaEdits(
          strokes: [
            EditorStroke(
              points: [Offset(0.2, 0.2), Offset(0.8, 0.8)],
              color: Colors.green,
              strokeWidthNormalized: 0.03,
              brushType: EditorBrushType.highlighter,
            ),
          ],
        ),
      );
      expect(png, isNotNull);
      expect(png!.isNotEmpty, isTrue);
    });
  });

  group('ChatMediaEditorScreen widget', () {
    testWidgets('shows draw controls, dot size slider, and crop presets for photo', (
      tester,
    ) async {
      final photoBytes = _makePng(300, 300);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatMediaEditorScreen(
            items: [
              MediaEditorItem(
                id: 'p1',
                originalBytes: photoBytes,
                isVideo: false,
              ),
            ],
            initialImageQuality: ImageQuality.high,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Quality pill & Send button visible
      expect(find.text('High'), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);

      // Open Draw mode
      await tester.tap(find.byTooltip('Draw'));
      await tester.pumpAndSettle();
      expect(find.text('Marker'), findsOneWidget);
      expect(find.text('Highlighter'), findsOneWidget);
      expect(find.byType(SignalDotSizeSlider), findsOneWidget);
      expect(find.byType(SignalColorSlider), findsOneWidget);

      // Switch to Highlighter
      await tester.tap(find.text('Highlighter'));
      await tester.pumpAndSettle();

      // Open Crop & Rotate mode
      await tester.tap(find.byTooltip('Crop & Rotate'));
      await tester.pumpAndSettle();
      expect(find.text('Free'), findsOneWidget);
      expect(find.text('1:1'), findsOneWidget);
      expect(find.text('16:9'), findsOneWidget);
      expect(find.byTooltip('Rotate 90°'), findsOneWidget);

      // Rotate 90° and commit Done
      await tester.tap(find.byTooltip('Rotate 90°'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // Undo button should now be visible since item was rotated
      expect(find.byTooltip('Undo'), findsOneWidget);
    });

    testWidgets('supports video item and multi-item thumbnail strip', (
      tester,
    ) async {
      final photoBytes = _makePng(120, 120);
      final fakeVideoBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5]);
      await tester.pumpWidget(
        MaterialApp(
          home: ChatMediaEditorScreen(
            items: [
              MediaEditorItem(
                id: 'v1',
                originalBytes: fakeVideoBytes,
                isVideo: true,
              ),
              MediaEditorItem(
                id: 'p2',
                originalBytes: photoBytes,
                isVideo: false,
              ),
            ],
            initialVideoQuality: VideoQuality.medium,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Medium (720p)'), findsOneWidget);
      expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
      expect(find.byTooltip('Draw'), findsOneWidget);
      expect(find.byTooltip('Stickers'), findsOneWidget);
      expect(find.byTooltip('Crop & Rotate'), findsOneWidget);
    });
  });
}
