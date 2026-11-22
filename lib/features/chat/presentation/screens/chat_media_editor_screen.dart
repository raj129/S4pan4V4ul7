import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../application/media/image_compressor.dart';
import '../../application/media/media_editor_exporter.dart';
import '../../application/media/video_compressor.dart';
import '../../application/services/giphy_media_service.dart';
import '../../domain/repositories/sticker_pack_repository.dart';
import '../widgets/image_quality_sheet.dart';
import '../widgets/media_editor/media_editor_crop_overlay.dart';
import '../widgets/media_editor/media_editor_draw_controls.dart';
import '../widgets/media_editor/media_editor_models.dart';
import '../widgets/media_editor/media_editor_sticker_layer.dart';
import '../widgets/video_quality_sheet.dart';

/// Signal-style full-screen photo & video editor before sending in chat.
class ChatMediaEditorScreen extends StatefulWidget {
  const ChatMediaEditorScreen({
    super.key,
    required this.items,
    this.initialImageQuality = ImageQuality.high,
    this.initialVideoQuality = VideoQuality.high,
    this.stickerPack,
    this.giphyService,
    this.exporter = const MediaEditorExporter(),
    this.videoCompressor = const VideoCompressor(),
  });

  final List<MediaEditorItem> items;
  final ImageQuality initialImageQuality;
  final VideoQuality initialVideoQuality;
  final StickerPackRepository? stickerPack;
  final GiphyMediaService? giphyService;
  final MediaEditorExporter exporter;
  final VideoCompressor videoCompressor;

  static Future<MediaEditorResult?> open(
    BuildContext context, {
    required List<MediaEditorItem> items,
    ImageQuality initialImageQuality = ImageQuality.high,
    VideoQuality initialVideoQuality = VideoQuality.high,
    StickerPackRepository? stickerPack,
    GiphyMediaService? giphyService,
  }) {
    return Navigator.of(context).push<MediaEditorResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ChatMediaEditorScreen(
          items: items,
          initialImageQuality: initialImageQuality,
          initialVideoQuality: initialVideoQuality,
          stickerPack: stickerPack,
          giphyService: giphyService,
        ),
      ),
    );
  }

  @override
  State<ChatMediaEditorScreen> createState() => _ChatMediaEditorScreenState();
}

class _ChatMediaEditorScreenState extends State<ChatMediaEditorScreen> {
  int _activeIndex = 0;
  EditorTool _tool = EditorTool.none;

  // Drawing state
  EditorBrushType _brushType = EditorBrushType.marker;
  Color _brushColor = const Color(0xFFFF3B30);
  double _strokeWidthNorm = 0.022;
  EditorStroke? _activeStroke;

  // Crop backup for Cancel
  MediaEdits? _preCropEdits;

  // Sticker drag-to-trash state
  bool _draggingSticker = false;
  bool _stickerOverTrash = false;

  // Quality selections
  late ImageQuality _imageQuality;
  late VideoQuality _videoQuality;

  // Decoded image & video state per item
  final Map<String, ui.Image> _decodedImages = {};
  final Map<String, Size> _mediaSizes = {};
  VideoPlayerController? _videoController;
  File? _tempVideoFile;
  bool _videoInitialized = false;
  bool _videoPlaying = false;
  bool _exporting = false;

  MediaEditorItem get _currentItem => widget.items[_activeIndex];

  @override
  void initState() {
    super.initState();
    _imageQuality = widget.initialImageQuality;
    _videoQuality = widget.initialVideoQuality;
    _loadCurrentMedia();
  }

  @override
  void dispose() {
    _disposeVideo();
    for (final img in _decodedImages.values) {
      img.dispose();
    }
    super.dispose();
  }

  Future<void> _disposeVideo() async {
    final controller = _videoController;
    _videoController = null;
    _videoInitialized = false;
    _videoPlaying = false;
    await controller?.dispose();
    final f = _tempVideoFile;
    _tempVideoFile = null;
    if (f != null) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  Future<void> _loadCurrentMedia() async {
    final item = _currentItem;
    await _disposeVideo();
    if (!mounted) return;

    if (!item.isVideo) {
      if (!_decodedImages.containsKey(item.id)) {
        try {
          final img = await MediaEditorExporter.decodeUiImage(
            item.originalBytes,
          );
          if (!mounted) {
            img.dispose();
            return;
          }
          setState(() {
            _decodedImages[item.id] = img;
            _mediaSizes[item.id] = Size(
              img.width.toDouble(),
              img.height.toDouble(),
            );
          });
        } catch (_) {}
      }
      return;
    }

    // Video preview via VideoPlayerController
    try {
      final meta = await widget.videoCompressor.extractMetadata(
        item.originalBytes,
      );
      if (mounted && meta.width > 0 && meta.height > 0) {
        setState(() {
          _mediaSizes[item.id] = Size(
            meta.width.toDouble(),
            meta.height.toDouble(),
          );
        });
      }
      final dir = await getTemporaryDirectory();
      final tempFile = File(
        '${dir.path}${Platform.pathSeparator}editor_vid_${item.id}.mp4',
      );
      await tempFile.writeAsBytes(item.originalBytes, flush: true);
      final controller = VideoPlayerController.file(tempFile);
      _tempVideoFile = tempFile;
      _videoController = controller;
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) return;
      setState(() {
        _videoInitialized = true;
        if (!_mediaSizes.containsKey(item.id) &&
            controller.value.size.width > 0) {
          _mediaSizes[item.id] = controller.value.size;
        }
      });
    } catch (_) {
      // Fallback gracefully in environments without video codec (e.g. widget tests)
      if (mounted) {
        setState(() {
          _videoInitialized = false;
          _mediaSizes.putIfAbsent(item.id, () => const Size(9, 16));
        });
      }
    }
  }

  Size _rotatedMediaSize(MediaEditorItem item) {
    final base = _mediaSizes[item.id] ?? const Size(1080, 1440);
    final swap = (item.edits.rotationQuarterTurns % 2) == 1;
    return swap ? Size(base.height, base.width) : base;
  }

  double _croppedAspectRatio(MediaEditorItem item) {
    final rot = _rotatedMediaSize(item);
    final crop = item.edits.cropRect;
    final w = rot.width * crop.width;
    final h = rot.height * crop.height;
    if (w <= 0 || h <= 0) return 1.0;
    return w / h;
  }

  Future<bool> _confirmDiscard() async {
    final anyEdited = widget.items.any((i) => i.edits.hasEdits);
    if (!anyEdited) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard edits?'),
        content: const Text(
          'Your drawings, crops, and stickers will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  void _undo() {
    final edits = _currentItem.edits;
    if (edits.strokes.isNotEmpty) {
      setState(() {
        _currentItem.edits = edits.copyWith(
          strokes: edits.strokes.sublist(0, edits.strokes.length - 1),
        );
      });
    } else if (edits.stickers.isNotEmpty) {
      setState(() {
        _currentItem.edits = edits.copyWith(
          stickers: edits.stickers.sublist(0, edits.stickers.length - 1),
        );
      });
    } else if (edits.isCropped || edits.rotationQuarterTurns != 0) {
      setState(() {
        _currentItem.edits = edits.copyWith(
          cropRect: const Rect.fromLTWH(0, 0, 1, 1),
          rotationQuarterTurns: 0,
        );
      });
    }
  }

  Future<void> _openStickerPicker() async {
    final picked = await MediaEditorStickerPickerSheet.show(
      context,
      stickerPack: widget.stickerPack,
      giphyService: widget.giphyService,
    );
    if (picked == null || !mounted) return;
    final crop = _currentItem.edits.cropRect;
    final placed = picked.copyWith(center: crop.center);
    setState(() {
      _tool = EditorTool.stickers;
      _currentItem.edits = _currentItem.edits.copyWith(
        stickers: [..._currentItem.edits.stickers, placed],
      );
    });
  }

  Future<void> _pickQuality() async {
    if (_currentItem.isVideo) {
      final chosen = await VideoQualitySheet.show(
        context,
        originalBytes: _currentItem.originalBytes.length,
        selected: _videoQuality,
        videoBytes: _currentItem.originalBytes,
      );
      if (chosen != null && mounted) {
        setState(() => _videoQuality = chosen);
      }
    } else {
      final chosen = await ImageQualitySheet.show(
        context,
        originalBytes: _currentItem.originalBytes.length,
        selected: _imageQuality,
        imageBytes: _currentItem.originalBytes,
      );
      if (chosen != null && mounted) {
        setState(() => _imageQuality = chosen);
      }
    }
  }

  Future<void> _send() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    await _videoController?.pause();

    try {
      final exported = <MediaEditorExportedItem>[];
      for (final item in widget.items) {
        final wasEdited = item.edits.hasEdits;
        Uint8List outBytes = item.originalBytes;
        if (wasEdited) {
          if (!item.isVideo) {
            outBytes = await widget.exporter.exportEditedPhoto(
              item.originalBytes,
              item.edits,
            );
          } else {
            final rotSize = _rotatedMediaSize(item);
            final croppedSize = Size(
              rotSize.width * item.edits.cropRect.width,
              rotSize.height * item.edits.cropRect.height,
            );
            final overlayPng = await widget.exporter.exportVideoOverlayPng(
              croppedSize,
              item.edits,
            );
            outBytes = await widget.videoCompressor.exportEdited(
              bytes: item.originalBytes,
              overlayPng: overlayPng,
              rotationQuarterTurns: item.edits.rotationQuarterTurns,
              cropLeft: item.edits.cropRect.left,
              cropTop: item.edits.cropRect.top,
              cropRight: item.edits.cropRect.right,
              cropBottom: item.edits.cropRect.bottom,
              targetHeight: _videoQuality.targetHeight,
            );
          }
        }
        exported.add(
          MediaEditorExportedItem(
            id: item.id,
            bytes: outBytes,
            isVideo: item.isVideo,
            wasEdited: wasEdited,
            filename: item.filename,
            sourceUri: wasEdited ? null : item.sourceUri,
            sourceFlags: wasEdited ? 0 : item.sourceFlags,
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(
        MediaEditorResult(
          items: exported,
          imageQuality: _imageQuality,
          videoQuality: _videoQuality,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _exporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export media: $e')),
      );
    }
  }

  Offset _canvasToNormalized(Offset localPos, Size canvasSize) {
    final crop = _currentItem.edits.cropRect;
    final fx = (localPos.dx / canvasSize.width.clamp(1.0, 9999.0)).clamp(
      0.0,
      1.0,
    );
    final fy = (localPos.dy / canvasSize.height.clamp(1.0, 9999.0)).clamp(
      0.0,
      1.0,
    );
    return Offset(crop.left + fx * crop.width, crop.top + fy * crop.height);
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    final inCropMode = _tool == EditorTool.crop;
    final inDrawMode = _tool == EditorTool.draw;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (inCropMode) {
          setState(() {
            if (_preCropEdits != null) item.edits = _preCropEdits!;
            _preCropEdits = null;
            _tool = EditorTool.none;
          });
          return;
        }
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  if (!inCropMode) _buildTopBar(item),
                  Expanded(
                    child: inCropMode
                        ? _buildCropStage(item)
                        : _buildMainStage(item, inDrawMode),
                  ),
                  if (!inCropMode) _buildBottomBar(item, inDrawMode),
                ],
              ),
              if (inDrawMode)
                Positioned(
                  right: 8,
                  top: 76,
                  bottom: 120,
                  child: Center(
                    child: SignalColorSlider(
                      color: _brushColor,
                      onChanged: (c) => setState(() => _brushColor = c),
                    ),
                  ),
                ),
              if (_draggingSticker)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 92,
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _stickerOverTrash ? 60 : 48,
                      height: _stickerOverTrash ? 60 : 48,
                      decoration: BoxDecoration(
                        color: _stickerOverTrash
                            ? Colors.redAccent
                            : Colors.black54,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white54, width: 1.5),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              if (_exporting)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(color: Colors.white),
                          const SizedBox(height: 12),
                          Text(
                            item.isVideo
                                ? 'Preparing video...'
                                : 'Preparing media...',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(MediaEditorItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Close',
            onPressed: () async {
              if (await _confirmDiscard() && mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.close, color: Colors.white),
          ),
          const Spacer(),
          if (item.edits.hasEdits)
            IconButton(
              tooltip: 'Undo',
              onPressed: _undo,
              icon: const Icon(Icons.undo, color: Colors.white),
            ),
          IconButton(
            tooltip: 'Draw',
            onPressed: () => setState(() {
              _tool = _tool == EditorTool.draw
                  ? EditorTool.none
                  : EditorTool.draw;
            }),
            icon: Icon(
              Icons.brush,
              color: _tool == EditorTool.draw
                  ? const Color(0xFF4C8DFF)
                  : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Stickers',
            onPressed: _openStickerPicker,
            icon: Icon(
              Icons.emoji_emotions_outlined,
              color: _tool == EditorTool.stickers
                  ? const Color(0xFF4C8DFF)
                  : Colors.white,
            ),
          ),
          IconButton(
            tooltip: 'Crop & Rotate',
            onPressed: () => setState(() {
              _preCropEdits = item.edits;
              _tool = EditorTool.crop;
            }),
            icon: const Icon(Icons.crop_rotate, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildMainStage(MediaEditorItem item, bool inDrawMode) {
    final aspect = _croppedAspectRatio(item);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;
        double stageW = maxW;
        double stageH = stageW / aspect;
        if (stageH > maxH) {
          stageH = maxH;
          stageW = stageH * aspect;
        }
        final stageSize = Size(
          math.max(1.0, stageW),
          math.max(1.0, stageH),
        );

        return Center(
          child: SizedBox(
            width: stageSize.width,
            height: stageSize.height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Underlying photo or video
                _buildCroppedMediaLayer(item),
                // Strokes painter
                CustomPaint(
                  painter: MediaStrokesPainter(
                    strokes: item.edits.strokes,
                    cropRect: item.edits.cropRect,
                    activeStroke: _activeStroke,
                  ),
                ),
                // Stickers layer
                MediaEditorStickerLayer(
                  stickers: item.edits.stickers,
                  cropRect: item.edits.cropRect,
                  canvasSize: stageSize,
                  interactive: !inDrawMode,
                  onUpdateSticker: (updated) {
                    setState(() {
                      item.edits = item.edits.copyWith(
                        stickers: item.edits.stickers
                            .map((s) => s.id == updated.id ? updated : s)
                            .toList(growable: false),
                      );
                    });
                  },
                  onBringToFront: (id) {
                    final list = [...item.edits.stickers];
                    final idx = list.indexWhere((s) => s.id == id);
                    if (idx >= 0 && idx < list.length - 1) {
                      final s = list.removeAt(idx);
                      list.add(s);
                      setState(() {
                        item.edits = item.edits.copyWith(stickers: list);
                      });
                    }
                  },
                  onDeleteSticker: (id) {
                    setState(() {
                      item.edits = item.edits.copyWith(
                        stickers: item.edits.stickers
                            .where((s) => s.id != id)
                            .toList(growable: false),
                      );
                    });
                  },
                  onDragStateChanged: (dragging, overTrash) {
                    setState(() {
                      _draggingSticker = dragging;
                      _stickerOverTrash = overTrash;
                    });
                  },
                ),
                // Drawing gesture detector when in draw mode
                if (inDrawMode)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) {
                      final pt = _canvasToNormalized(
                        d.localPosition,
                        stageSize,
                      );
                      setState(() {
                        _activeStroke = EditorStroke(
                          points: [pt],
                          color: _brushColor,
                          strokeWidthNormalized: _strokeWidthNorm,
                          brushType: _brushType,
                        );
                      });
                    },
                    onPanUpdate: (d) {
                      final current = _activeStroke;
                      if (current == null) return;
                      final pt = _canvasToNormalized(
                        d.localPosition,
                        stageSize,
                      );
                      setState(() {
                        _activeStroke = current.copyWith(
                          points: [...current.points, pt],
                        );
                      });
                    },
                    onPanEnd: (_) {
                      final finished = _activeStroke;
                      if (finished == null) return;
                      setState(() {
                        _activeStroke = null;
                        item.edits = item.edits.copyWith(
                          strokes: [...item.edits.strokes, finished],
                        );
                      });
                    },
                    onPanCancel: () => setState(() => _activeStroke = null),
                  ),
                // Video play/pause tap overlay when not drawing
                if (item.isVideo && !inDrawMode)
                  Center(
                    child: IconButton(
                      iconSize: 52,
                      onPressed: _videoInitialized
                          ? () {
                              final c = _videoController!;
                              if (c.value.isPlaying) {
                                c.pause();
                                setState(() => _videoPlaying = false);
                              } else {
                                c.play();
                                setState(() => _videoPlaying = true);
                              }
                            }
                          : null,
                      icon: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Colors.black45,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _videoPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCroppedMediaLayer(MediaEditorItem item) {
    if (!item.isVideo) {
      final img = _decodedImages[item.id];
      if (img == null) {
        return Image.memory(item.originalBytes, fit: BoxFit.contain);
      }
      return CustomPaint(
        painter: _CroppedUiImagePainter(
          image: img,
          cropRect: item.edits.cropRect,
          rotationQuarterTurns: item.edits.rotationQuarterTurns,
        ),
      );
    }

    if (_videoInitialized && _videoController != null) {
      final rotSize = _rotatedMediaSize(item);
      final crop = item.edits.cropRect;
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: rotSize.width * crop.width,
            height: rotSize.height * crop.height,
            child: OverflowBox(
              maxWidth: double.infinity,
              maxHeight: double.infinity,
              alignment: Alignment(
                crop.width >= 1.0
                    ? 0
                    : -1 + 2 * (crop.left / (1.0 - crop.width)),
                crop.height >= 1.0
                    ? 0
                    : -1 + 2 * (crop.top / (1.0 - crop.height)),
              ),
              child: SizedBox(
                width: rotSize.width,
                height: rotSize.height,
                child: RotatedBox(
                  quarterTurns: item.edits.rotationQuarterTurns,
                  child: VideoPlayer(_videoController!),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF18181B),
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam_outlined, color: Colors.white54, size: 48),
          SizedBox(height: 8),
          Text('Video preview', style: TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }

  Widget _buildCropStage(MediaEditorItem item) {
    final rotSize = _rotatedMediaSize(item);
    final aspect = rotSize.width / rotSize.height.clamp(1.0, 99999.0);
    return MediaEditorCropOverlay(
      cropRect: item.edits.cropRect,
      mediaAspectRatio: aspect,
      mediaChild: _buildUncroppedRotatedMedia(item),
      onCropRectChanged: (next) {
        setState(() {
          item.edits = item.edits.copyWith(cropRect: next);
        });
      },
      onRotate90: () {
        setState(() {
          item.edits = item.edits.rotated90Clockwise();
        });
      },
      onReset: () {
        setState(() {
          item.edits = item.edits.copyWith(
            cropRect: const Rect.fromLTWH(0, 0, 1, 1),
            rotationQuarterTurns: 0,
          );
        });
      },
      onDone: () {
        setState(() {
          _preCropEdits = null;
          _tool = EditorTool.none;
        });
      },
      onCancel: () {
        setState(() {
          if (_preCropEdits != null) item.edits = _preCropEdits!;
          _preCropEdits = null;
          _tool = EditorTool.none;
        });
      },
    );
  }

  Widget _buildUncroppedRotatedMedia(MediaEditorItem item) {
    if (!item.isVideo) {
      final img = _decodedImages[item.id];
      if (img == null) {
        return RotatedBox(
          quarterTurns: item.edits.rotationQuarterTurns,
          child: Image.memory(item.originalBytes, fit: BoxFit.contain),
        );
      }
      return CustomPaint(
        painter: _CroppedUiImagePainter(
          image: img,
          cropRect: const Rect.fromLTWH(0, 0, 1, 1),
          rotationQuarterTurns: item.edits.rotationQuarterTurns,
        ),
      );
    }
    if (_videoInitialized && _videoController != null) {
      return RotatedBox(
        quarterTurns: item.edits.rotationQuarterTurns,
        child: VideoPlayer(_videoController!),
      );
    }
    return Container(
      color: const Color(0xFF18181B),
      alignment: Alignment.center,
      child: const Icon(
        Icons.videocam_outlined,
        color: Colors.white54,
        size: 48,
      ),
    );
  }

  Widget _buildBottomBar(MediaEditorItem item, bool inDrawMode) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inDrawMode) ...[
            SignalBrushTypeToggle(
              brushType: _brushType,
              onChanged: (t) => setState(() => _brushType = t),
            ),
            const SizedBox(height: 8),
            SignalDotSizeSlider(
              value: _strokeWidthNorm,
              color: _brushColor,
              isHighlighter: _brushType == EditorBrushType.highlighter,
              onChanged: (v) => setState(() => _strokeWidthNorm = v),
            ),
            const SizedBox(height: 8),
          ],
          if (widget.items.length > 1) ...[
            SizedBox(
              height: 54,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final thumb = widget.items[index];
                  final selected = index == _activeIndex;
                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        _activeIndex = index;
                        _tool = EditorTool.none;
                      });
                      _loadCurrentMedia();
                    },
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: selected ? Colors.white : Colors.white24,
                          width: selected ? 2.5 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (!thumb.isVideo)
                            Image.memory(thumb.originalBytes, fit: BoxFit.cover)
                          else
                            const ColoredBox(
                              color: Color(0xFF27272A),
                              child: Icon(
                                Icons.play_circle_outline,
                                color: Colors.white70,
                              ),
                            ),
                          if (thumb.edits.hasEdits)
                            const Positioned(
                              right: 3,
                              top: 3,
                              child: CircleAvatar(
                                radius: 4,
                                backgroundColor: Color(0xFF4C8DFF),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              // Quality pill
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: _pickQuality,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.hd_outlined, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        item.isVideo
                            ? _videoQuality.label
                            : _imageQuality.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Signal-style Send button
              FloatingActionButton(
                heroTag: 'media_editor_send',
                onPressed: _exporting ? null : _send,
                backgroundColor: const Color(0xFF2C6BED),
                foregroundColor: Colors.white,
                child: const Icon(Icons.send),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CroppedUiImagePainter extends CustomPainter {
  const _CroppedUiImagePainter({
    required this.image,
    required this.cropRect,
    required this.rotationQuarterTurns,
  });

  final ui.Image image;
  final Rect cropRect;
  final int rotationQuarterTurns;

  @override
  void paint(Canvas canvas, Size size) {
    final turns = rotationQuarterTurns % 4;
    final swap = turns % 2 == 1;
    final rotW = (swap ? image.height : image.width).toDouble();
    final rotH = (swap ? image.width : image.height).toDouble();
    final rawOutW = rotW * cropRect.width;
    final rawOutH = rotH * cropRect.height;
    if (rawOutW <= 0 || rawOutH <= 0) return;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / rawOutW, size.height / rawOutH);
    canvas.translate(-cropRect.left * rotW, -cropRect.top * rotH);
    canvas.translate(rotW / 2, rotH / 2);
    canvas.rotate(turns * (math.pi / 2));
    canvas.translate(-image.width / 2, -image.height / 2);
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CroppedUiImagePainter oldDelegate) {
    return oldDelegate.image != image ||
        oldDelegate.cropRect != cropRect ||
        oldDelegate.rotationQuarterTurns != rotationQuarterTurns;
  }
}
