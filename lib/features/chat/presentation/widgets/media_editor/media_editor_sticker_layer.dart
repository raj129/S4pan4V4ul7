import 'dart:async';
import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';

import '../../../application/media/media_editor_exporter.dart';
import '../../../application/services/giphy_media_service.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/entities/giphy_media.dart';
import '../../../domain/entities/local_sticker.dart';
import '../../../domain/repositories/sticker_pack_repository.dart';
import 'media_editor_models.dart';

/// Interactive Signal-style sticker overlay supporting drag, two-finger
/// pinch-to-scale & rotate, tap-to-front, and drag-to-trash deletion.
class MediaEditorStickerLayer extends StatefulWidget {
  const MediaEditorStickerLayer({
    super.key,
    required this.stickers,
    required this.cropRect,
    required this.canvasSize,
    required this.interactive,
    required this.onUpdateSticker,
    required this.onBringToFront,
    required this.onDeleteSticker,
    required this.onDragStateChanged,
  });

  final List<EditorSticker> stickers;
  final Rect cropRect;
  final Size canvasSize;
  final bool interactive;
  final ValueChanged<EditorSticker> onUpdateSticker;
  final ValueChanged<String> onBringToFront;
  final ValueChanged<String> onDeleteSticker;
  final void Function(bool isDragging, bool isOverTrash) onDragStateChanged;

  @override
  State<MediaEditorStickerLayer> createState() =>
      _MediaEditorStickerLayerState();
}

class _MediaEditorStickerLayerState extends State<MediaEditorStickerLayer> {
  String? _activeId;
  Offset? _startFocal;
  Offset? _startCenter;
  double _startScale = 1.0;
  double _startRotation = 0.0;
  bool _overTrash = false;

  Offset _mapToCanvas(Offset norm) {
    final cropW = widget.cropRect.width <= 0 ? 1.0 : widget.cropRect.width;
    final cropH = widget.cropRect.height <= 0 ? 1.0 : widget.cropRect.height;
    return Offset(
      ((norm.dx - widget.cropRect.left) / cropW) * widget.canvasSize.width,
      ((norm.dy - widget.cropRect.top) / cropH) * widget.canvasSize.height,
    );
  }

  bool _isNearTrash(Offset canvasPos) {
    final trashCenter = Offset(
      widget.canvasSize.width / 2,
      widget.canvasSize.height - 28,
    );
    return (canvasPos - trashCenter).distance <= 52;
  }

  @override
  Widget build(BuildContext context) {
    final baseSize =
        widget.canvasSize.shortestSide * MediaEditorExporter.stickerBaseFraction;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (final sticker in widget.stickers)
            _buildStickerItem(sticker, baseSize),
        ],
      ),
    );
  }

  Widget _buildStickerItem(EditorSticker sticker, double baseSize) {
    final pos = _mapToCanvas(sticker.center);
    final isSelected = _activeId == sticker.id;

    Widget content;
    if (sticker.kind == EditorStickerKind.emoji && sticker.emoji != null) {
      content = Text(
        sticker.emoji!,
        style: TextStyle(fontSize: baseSize * 0.82, height: 1.0),
      );
    } else if (sticker.kind == EditorStickerKind.imageBytes &&
        sticker.imageBytes != null) {
      content = Image.memory(
        sticker.imageBytes!,
        width: baseSize,
        height: baseSize,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      );
    } else {
      content = const SizedBox.shrink();
    }

    final transformed = Transform.rotate(
      angle: sticker.rotation,
      child: Transform.scale(
        scale: sticker.scale,
        child: Container(
          width: baseSize,
          height: baseSize,
          alignment: Alignment.center,
          decoration: isSelected && widget.interactive
              ? BoxDecoration(
                  border: Border.all(
                    color: _overTrash ? Colors.redAccent : Colors.white70,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: content,
        ),
      ),
    );

    return Positioned(
      left: pos.dx - baseSize / 2,
      top: pos.dy - baseSize / 2,
      width: baseSize,
      height: baseSize,
      child: IgnorePointer(
        ignoring: !widget.interactive,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            widget.onBringToFront(sticker.id);
            setState(() => _activeId = sticker.id);
          },
          onScaleStart: (details) {
            widget.onBringToFront(sticker.id);
            setState(() {
              _activeId = sticker.id;
              _startFocal = details.focalPoint;
              _startCenter = sticker.center;
              _startScale = sticker.scale;
              _startRotation = sticker.rotation;
              _overTrash = false;
            });
            widget.onDragStateChanged(true, false);
          },
          onScaleUpdate: (details) {
            if (_startFocal == null || _startCenter == null) return;
            final delta = details.focalPoint - _startFocal!;
            final cropW = widget.cropRect.width <= 0
                ? 1.0
                : widget.cropRect.width;
            final cropH = widget.cropRect.height <= 0
                ? 1.0
                : widget.cropRect.height;
            final normDx =
                (delta.dx / widget.canvasSize.width.clamp(1.0, 9999.0)) * cropW;
            final normDy =
                (delta.dy / widget.canvasSize.height.clamp(1.0, 9999.0)) *
                cropH;
            final nextCenter = Offset(
              (_startCenter!.dx + normDx).clamp(
                widget.cropRect.left - 0.1,
                widget.cropRect.right + 0.1,
              ),
              (_startCenter!.dy + normDy).clamp(
                widget.cropRect.top - 0.1,
                widget.cropRect.bottom + 0.1,
              ),
            );
            final canvasPos = _mapToCanvas(nextCenter);
            final over = _isNearTrash(canvasPos);
            if (over != _overTrash) {
              setState(() => _overTrash = over);
            }
            widget.onDragStateChanged(true, over);
            widget.onUpdateSticker(
              sticker.copyWith(
                center: nextCenter,
                scale: (_startScale * details.scale).clamp(0.35, 4.0),
                rotation: _startRotation + details.rotation,
              ),
            );
          },
          onScaleEnd: (_) {
            final shouldDelete = _overTrash;
            final id = sticker.id;
            setState(() {
              _overTrash = false;
              _startFocal = null;
              _startCenter = null;
              if (shouldDelete) _activeId = null;
            });
            widget.onDragStateChanged(false, false);
            if (shouldDelete) {
              widget.onDeleteSticker(id);
            }
          },
          child: transformed,
        ),
      ),
    );
  }
}

/// Signal-style sticker & emoji picker sheet with Emoji, Personal stickers,
/// and Giphy stickers tabs.
class MediaEditorStickerPickerSheet extends StatefulWidget {
  const MediaEditorStickerPickerSheet({
    super.key,
    this.stickerPack,
    this.giphyService,
  });

  final StickerPackRepository? stickerPack;
  final GiphyMediaService? giphyService;

  static Future<EditorSticker?> show(
    BuildContext context, {
    StickerPackRepository? stickerPack,
    GiphyMediaService? giphyService,
  }) {
    return showModalBottomSheet<EditorSticker>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1A1A1D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.56,
        child: MediaEditorStickerPickerSheet(
          stickerPack: stickerPack,
          giphyService: giphyService,
        ),
      ),
    );
  }

  @override
  State<MediaEditorStickerPickerSheet> createState() =>
      _MediaEditorStickerPickerSheetState();
}

class _MediaEditorStickerPickerSheetState
    extends State<MediaEditorStickerPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final GiphyMediaService _giphy;
  final TextEditingController _giphySearchController = TextEditingController();

  List<LocalSticker> _personalStickers = const [];
  final Map<String, Uint8List> _personalBytes = {};
  bool _loadingPersonal = false;

  List<GiphyMedia> _giphyResults = const [];
  bool _loadingGiphy = false;
  String? _giphyError;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _giphy = widget.giphyService ?? GiphyMediaService();
    _loadPersonalStickers();
    _searchGiphy('');
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _giphySearchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPersonalStickers() async {
    final repo = widget.stickerPack;
    if (repo == null) return;
    setState(() => _loadingPersonal = true);
    try {
      final list = await repo.list();
      if (!mounted) return;
      setState(() => _personalStickers = list);
      for (final s in list) {
        try {
          final bytes = await repo.readBytes(s);
          if (mounted) {
            setState(() => _personalBytes[s.id] = bytes);
          }
        } catch (_) {}
      }
    } finally {
      if (mounted) setState(() => _loadingPersonal = false);
    }
  }

  Future<void> _searchGiphy(String query) async {
    setState(() {
      _loadingGiphy = true;
      _giphyError = null;
    });
    try {
      final page = await _giphy.search(
        query: query,
        type: MessageType.sticker,
      );
      if (!mounted) return;
      setState(() => _giphyResults = page.results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _giphyError = 'Could not load Giphy stickers.');
    } finally {
      if (mounted) setState(() => _loadingGiphy = false);
    }
  }

  Future<void> _pickGiphy(GiphyMedia media) async {
    try {
      final bytes = await _giphy.download(media);
      if (!mounted) return;
      Navigator.of(context).pop(
        EditorSticker(
          id: 'giphy_${DateTime.now().microsecondsSinceEpoch}',
          kind: EditorStickerKind.imageBytes,
          center: const Offset(0.5, 0.5),
          imageBytes: bytes,
          label: media.title,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not download sticker.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.white,
            tabs: const [
              Tab(text: 'Emoji'),
              Tab(text: 'Personal'),
              Tab(text: 'Giphy'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildEmojiTab(),
                _buildPersonalTab(),
                _buildGiphyTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmojiTab() {
    return EmojiPicker(
      onEmojiSelected: (_, emoji) {
        Navigator.of(context).pop(
          EditorSticker(
            id: 'emoji_${DateTime.now().microsecondsSinceEpoch}',
            kind: EditorStickerKind.emoji,
            center: const Offset(0.5, 0.5),
            emoji: emoji.emoji,
          ),
        );
      },
      config: const Config(
        height: 300,
        emojiViewConfig: EmojiViewConfig(
          backgroundColor: Color(0xFF1A1A1D),
          columns: 7,
          emojiSizeMax: 28,
        ),
        categoryViewConfig: CategoryViewConfig(
          backgroundColor: Color(0xFF1A1A1D),
          iconColorSelected: Colors.white,
          indicatorColor: Colors.white,
        ),
        bottomActionBarConfig: BottomActionBarConfig(enabled: false),
      ),
    );
  }

  Widget _buildPersonalTab() {
    if (widget.stickerPack == null) {
      return const Center(
        child: Text(
          'Personal stickers unavailable.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    if (_loadingPersonal && _personalStickers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_personalStickers.isEmpty) {
      return const Center(
        child: Text(
          'No personal stickers saved yet.',
          style: TextStyle(color: Colors.white60),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _personalStickers.length,
      itemBuilder: (context, index) {
        final s = _personalStickers[index];
        final bytes = _personalBytes[s.id];
        if (bytes == null) {
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).pop(
              EditorSticker(
                id: 'personal_${s.id}_${DateTime.now().microsecondsSinceEpoch}',
                kind: EditorStickerKind.imageBytes,
                center: const Offset(0.5, 0.5),
                imageBytes: bytes,
                label: s.label,
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        );
      },
    );
  }

  Widget _buildGiphyTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _giphySearchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search Giphy stickers...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onChanged: (q) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(
                const Duration(milliseconds: 350),
                () => _searchGiphy(q),
              );
            },
          ),
        ),
        Expanded(
          child: _loadingGiphy
              ? const Center(child: CircularProgressIndicator())
              : _giphyError != null
              ? Center(
                  child: Text(
                    _giphyError!,
                    style: const TextStyle(color: Colors.white60),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _giphyResults.length,
                  itemBuilder: (context, index) {
                    final media = _giphyResults[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _pickGiphy(media),
                      child: Image.network(
                        media.previewUrl,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white38,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
