import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/services/giphy_media_service.dart';
import '../../data/repositories/local_sticker_pack_repository.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/giphy_media.dart';
import '../../domain/entities/local_sticker.dart';

enum ChatMediaPickerTab { emoji, stickers, gifs }

enum _StickerSource { giphy, personal }

class ChatMediaPickerPanel extends StatefulWidget {
  const ChatMediaPickerPanel({
    required this.stickerPack,
    required this.buildEmojiPicker,
    required this.onSend,
    required this.onInsertEmoji,
    required this.onBackspace,
    required this.onClose,
    super.key,
  });

  final LocalStickerPackRepository stickerPack;
  final Widget Function(double height) buildEmojiPicker;
  final Future<void> Function(
    Uint8List bytes,
    MessageType type,
    String fileName,
  )
  onSend;
  final ValueChanged<String> onInsertEmoji;
  final VoidCallback onBackspace;
  final VoidCallback onClose;

  @override
  State<ChatMediaPickerPanel> createState() => _ChatMediaPickerPanelState();
}

class _ChatMediaPickerPanelState extends State<ChatMediaPickerPanel> {
  static const _columns = 3;
  static const _maxPages = 5;
  static final List<Emoji> _emojiCatalog = [
    for (final category in defaultEmojiSet) ...category.emoji,
  ];
  final _catalog = GiphyMediaService();
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();
  final _pageController = PageController();
  Timer? _debounce;
  List<GiphyMedia> _results = const [];
  List<LocalSticker> _stickers = const [];
  ChatMediaPickerTab _tab = ChatMediaPickerTab.emoji;
  _StickerSource _stickerSource = _StickerSource.giphy;
  int? _nextOffset;
  String? _error;
  String? _busyId;
  bool _loading = false;
  bool _loadingMore = false;
  bool _loadingStickers = false;
  bool _paginationFailed = false;
  bool _searchExpanded = false;
  int _pagesLoaded = 0;
  int _requestGeneration = 0;

  bool get _showGiphy =>
      _tab == ChatMediaPickerTab.gifs ||
      (_tab == ChatMediaPickerTab.stickers &&
          _stickerSource == _StickerSource.giphy);

  MessageType get _mediaType => _tab == ChatMediaPickerTab.stickers
      ? MessageType.sticker
      : MessageType.gif;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadNextWhenNearEnd);
    unawaited(_loadStickers());
  }

  @override
  void dispose() {
    _requestGeneration++;
    _debounce?.cancel();
    _scrollController
      ..removeListener(_loadNextWhenNearEnd)
      ..dispose();
    _pageController.dispose();
    _searchFocusNode.dispose();
    _searchController.dispose();
    _catalog.close();
    super.dispose();
  }

  Future<void> _search({required bool reset}) async {
    if (!_showGiphy) return;
    final generation = reset ? ++_requestGeneration : _requestGeneration;
    if (reset) {
      setState(() {
        _loading = true;
        _loadingMore = false;
        _error = null;
        _paginationFailed = false;
        _results = const [];
        _nextOffset = null;
        _pagesLoaded = 0;
      });
    } else {
      if (_loadingMore || _nextOffset == null) return;
      setState(() {
        _loadingMore = true;
        _error = null;
        _paginationFailed = false;
      });
    }
    try {
      final page = await _catalog.search(
        query: _searchController.text,
        type: _mediaType,
        offset: reset ? 0 : _nextOffset!,
      );
      if (!mounted || generation != _requestGeneration) return;
      final existingIds = _results.map((item) => item.id).toSet();
      setState(() {
        _results = reset
            ? page.results
            : [
                ..._results,
                ...page.results.where((item) => !existingIds.contains(item.id)),
              ];
        _nextOffset = page.nextOffset;
        _pagesLoaded++;
        if (_pagesLoaded >= _maxPages) _nextOffset = null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _error = error.toString().replaceFirst('Bad state: ', '');
        _loading = false;
        _loadingMore = false;
        _paginationFailed = !reset;
      });
    }
  }

  void _loadNextWhenNearEnd() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 500 &&
        _nextOffset != null &&
        !_paginationFailed) {
      unawaited(_search(reset: false));
    }
  }

  void _onQueryChanged(String _) {
    _requestGeneration++;
    _debounce?.cancel();
    if (_tab == ChatMediaPickerTab.emoji) {
      setState(() {});
      return;
    }
    if (_tab == ChatMediaPickerTab.stickers &&
        _stickerSource == _StickerSource.personal) {
      setState(() {});
      return;
    }
    if (!_showGiphy) return;
    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => unawaited(_search(reset: true)),
    );
  }

  void _selectTab(ChatMediaPickerTab tab) {
    if (_tab == tab) return;
    if (_pageController.hasClients) {
      unawaited(
        _pageController.animateToPage(
          tab.index,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        ),
      );
      return;
    }
    _activateTab(tab);
  }

  void _onPageChanged(int index) {
    final tab = ChatMediaPickerTab.values[index];
    if (_tab == tab) return;
    _activateTab(tab);
  }

  void _activateTab(ChatMediaPickerTab tab) {
    if (_tab == tab) return;
    _debounce?.cancel();
    _requestGeneration++;
    setState(() {
      _tab = tab;
    });
    if (tab == ChatMediaPickerTab.stickers) {
      unawaited(_loadStickers());
    }
    if (_showGiphy) {
      unawaited(_search(reset: true));
    }
  }

  void _expandSearch() {
    if (_searchExpanded) return;
    setState(() => _searchExpanded = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _collapseSearch() {
    if (!_searchExpanded) return;
    _searchFocusNode.unfocus();
    _searchController.clear();
    setState(() => _searchExpanded = false);
    _onQueryChanged('');
  }

  void _selectStickerSource(_StickerSource source) {
    if (_stickerSource == source) return;
    _debounce?.cancel();
    _requestGeneration++;
    setState(() {
      _stickerSource = source;
      _error = null;
    });
    if (source == _StickerSource.personal) {
      unawaited(_loadStickers());
    } else {
      unawaited(_search(reset: true));
    }
  }

  Future<void> _loadStickers() async {
    if (_loadingStickers) return;
    setState(() => _loadingStickers = true);
    try {
      final stickers = await widget.stickerPack.list();
      if (mounted) setState(() => _stickers = stickers);
    } catch (error) {
      if (mounted) _showError('Could not load your sticker pack: $error');
    } finally {
      if (mounted) setState(() => _loadingStickers = false);
    }
  }

  Future<void> _sendGiphy(GiphyMedia media) async {
    if (_busyId != null) return;
    setState(() => _busyId = media.id);
    Uint8List? bytes;
    try {
      bytes = await _catalog.download(media);
      await widget.onSend(
        bytes,
        media.type,
        'giphy_${media.id}.${media.extension}',
      );
    } catch (error) {
      if (mounted) _showError('Could not send this media: $error');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _saveGiphySticker(GiphyMedia media) async {
    if (_busyId != null) return;
    setState(() => _busyId = media.id);
    Uint8List? bytes;
    try {
      bytes = await _catalog.download(media);
      await widget.stickerPack.addSticker(
        bytes: bytes,
        extension: media.extension,
        label: media.title,
      );
      await _loadStickers();
      if (mounted) _showMessage('Saved to My stickers');
    } catch (error) {
      if (mounted) _showError('Could not save sticker: $error');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _sendLocalSticker(LocalSticker sticker) async {
    if (_busyId != null) return;
    setState(() => _busyId = sticker.id);
    Uint8List? bytes;
    try {
      bytes = await widget.stickerPack.readBytes(sticker);
      await widget.onSend(
        bytes,
        MessageType.sticker,
        'sticker_${sticker.id}.${sticker.extension}',
      );
    } catch (error) {
      if (mounted) _showError('Could not send sticker: $error');
    } finally {
      bytes?.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _importSticker() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['gif', 'webp', 'png', 'jpg', 'jpeg'],
      );
      if (file == null || !mounted) return;
      final size = await file.length();
      if (!mounted) return;
      if (size == null ||
          size < 1 ||
          size > LocalStickerPackRepository.maxStickerBytes) {
        throw StateError('Choose a sticker no larger than 4 MB.');
      }
      final extension = file.extension?.toLowerCase();
      if (extension == null) {
        throw const FormatException('File type is missing.');
      }
      final bytes = await file.readAsBytes();
      try {
        if (!mounted) return;
        if (bytes.length > LocalStickerPackRepository.maxStickerBytes) {
          throw StateError('Choose a sticker no larger than 4 MB.');
        }
        await widget.stickerPack.addSticker(
          bytes: bytes,
          extension: extension,
          label: file.name,
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      await _loadStickers();
      if (mounted) _showMessage('Added to My stickers');
    } catch (error) {
      if (mounted) _showError('Could not add sticker: $error');
    }
  }

  Future<void> _removeSticker(LocalSticker sticker) async {
    try {
      await widget.stickerPack.remove(sticker);
      if (mounted) {
        setState(
          () => _stickers = _stickers
              .where((item) => item.id != sticker.id)
              .toList(growable: false),
        );
      }
    } catch (error) {
      if (mounted) _showError('Could not remove sticker: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final availableHeight =
        mediaQuery.size.height - mediaQuery.viewInsets.bottom;
    final panelHeight = math
        .min(400.0, availableHeight * 0.62)
        .clamp(240.0, 400.0)
        .toDouble();
    final showPersonalStickers =
        _tab == ChatMediaPickerTab.stickers &&
        _stickerSource == _StickerSource.personal;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SizedBox(
        height: panelHeight,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: SizedBox(
                height: 36,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          key: const ValueKey('open-picker-search'),
                          tooltip: 'Search ${_tab.name}',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: _expandSearch,
                          icon: const Icon(Icons.search_rounded, size: 20),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _tabButton(
                                tab: ChatMediaPickerTab.emoji,
                                icon: Icons.emoji_emotions_outlined,
                                label: 'Emoji',
                              ),
                              _tabButton(
                                tab: ChatMediaPickerTab.stickers,
                                icon: Icons.sticky_note_2_outlined,
                                label: 'Stickers',
                              ),
                              _tabButton(
                                tab: ChatMediaPickerTab.gifs,
                                icon: Icons.gif_box_outlined,
                                label: 'GIFs',
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Backspace',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed:
                              _tab == ChatMediaPickerTab.emoji &&
                                  !_searchExpanded
                              ? widget.onBackspace
                              : null,
                          icon: const Icon(Icons.backspace_outlined, size: 19),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close media picker',
                          visualDensity: VisualDensity.compact,
                          constraints: const BoxConstraints.tightFor(
                            width: 36,
                            height: 36,
                          ),
                          padding: EdgeInsets.zero,
                          onPressed: widget.onClose,
                          icon: const Icon(Icons.close_rounded, size: 20),
                        ),
                      ],
                    ),
                    if (_searchExpanded)
                      Positioned(
                        left: 0,
                        right: 40,
                        top: 0,
                        bottom: 0,
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onChanged: _onQueryChanged,
                          textInputAction: TextInputAction.search,
                          maxLength: 50,
                          decoration: InputDecoration(
                            hintText: switch (_tab) {
                              ChatMediaPickerTab.emoji => 'Search emoji',
                              ChatMediaPickerTab.stickers
                                  when showPersonalStickers =>
                                'Search My stickers',
                              _ => 'Search GIPHY',
                            },
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 18,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                            suffixIcon: IconButton(
                              tooltip: 'Close search',
                              visualDensity: VisualDensity.compact,
                              constraints: const BoxConstraints.tightFor(
                                width: 32,
                                height: 32,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: _collapseSearch,
                              icon: const Icon(Icons.close_rounded, size: 18),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            isDense: true,
                            counterText: '',
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_tab == ChatMediaPickerTab.stickers)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedButton<_StickerSource>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(
                            value: _StickerSource.giphy,
                            label: Text('Explore'),
                          ),
                          ButtonSegment(
                            value: _StickerSource.personal,
                            label: Text('My stickers'),
                          ),
                        ],
                        selected: {_stickerSource},
                        onSelectionChanged: (selection) =>
                            _selectStickerSource(selection.first),
                      ),
                    ),
                    if (showPersonalStickers)
                      IconButton(
                        tooltip: 'Add sticker from device',
                        visualDensity: VisualDensity.compact,
                        onPressed: _importSticker,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                      ),
                  ],
                ),
              ),
            Expanded(
              child: PageView.builder(
                key: const ValueKey('chat-media-pages'),
                controller: _pageController,
                itemCount: ChatMediaPickerTab.values.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) =>
                    _buildPage(ChatMediaPickerTab.values[index], panelHeight),
              ),
            ),
            if (_showGiphy)
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 2, 8, 4),
                child: Text('Powered by GIPHY', style: TextStyle(fontSize: 11)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabButton({
    required ChatMediaPickerTab tab,
    required IconData icon,
    required String label,
  }) {
    final selected = _tab == tab;
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: Material(
          color: selected
              ? colors.primary.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            key: ValueKey('picker-tab-${tab.name}'),
            onTap: () => _selectTab(tab),
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(
                icon,
                size: 19,
                color: selected ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(ChatMediaPickerTab tab, double panelHeight) {
    if (tab != _tab) return const SizedBox.expand();
    if (tab == ChatMediaPickerTab.emoji) {
      final query = _searchController.text.trim().toLowerCase();
      if (query.isNotEmpty) return _buildEmojiSearchResults(query);
      return widget.buildEmojiPicker(math.max(180.0, panelHeight - 52));
    }
    if (tab == ChatMediaPickerTab.stickers &&
        _stickerSource == _StickerSource.personal) {
      return _buildPersonalStickers();
    }
    return _buildGiphyGrid();
  }

  Widget _buildEmojiSearchResults(String query) {
    final results = _emojiCatalog
        .where(
          (emoji) =>
              emoji.emoji.contains(query) ||
              emoji.keywords.any(
                (keyword) => keyword.toLowerCase().contains(query),
              ),
        )
        .take(120)
        .toList(growable: false);
    if (results.isEmpty) {
      return const Center(child: Text('No matching emoji.'));
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 8,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final emoji = results[index];
        return Tooltip(
          message: emoji.name,
          child: InkResponse(
            onTap: () => widget.onInsertEmoji(emoji.emoji),
            child: Center(
              child: Text(emoji.emoji, style: const TextStyle(fontSize: 26)),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGiphyGrid() {
    if (_loading && _results.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _results.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_search(reset: true)),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty) {
      return const Center(child: Text('No results. Try another search.'));
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount:
          _results.length + (_loadingMore || _paginationFailed ? _columns : 0),
      itemBuilder: (context, index) {
        if (index >= _results.length) {
          if (_paginationFailed) {
            return Center(
              child: TextButton(
                onPressed: () => unawaited(_search(reset: false)),
                child: const Text('Retry'),
              ),
            );
          }
          return const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }
        final media = _results[index];
        return _GiphyTile(
          key: ValueKey(media.id),
          media: media,
          busy: _busyId == media.id,
          onTap: () => unawaited(_sendGiphy(media)),
          onSave: _tab == ChatMediaPickerTab.stickers
              ? () => unawaited(_saveGiphySticker(media))
              : null,
        );
      },
    );
  }

  Widget _buildPersonalStickers() {
    if (_loadingStickers && _stickers.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final query = _searchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _stickers
        : _stickers
              .where((sticker) => sticker.label.toLowerCase().contains(query))
              .toList(growable: false);
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          _stickers.isEmpty
              ? 'Add a sticker from your device or GIPHY.'
              : 'No saved stickers match this search.',
          textAlign: TextAlign.center,
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final sticker = filtered[index];
        return _LocalStickerTile(
          key: ValueKey(sticker.id),
          sticker: sticker,
          repository: widget.stickerPack,
          busy: _busyId == sticker.id,
          onTap: () => unawaited(_sendLocalSticker(sticker)),
          onRemove: () => unawaited(_removeSticker(sticker)),
        );
      },
    );
  }
}

class _GiphyTile extends StatelessWidget {
  const _GiphyTile({
    super.key,
    required this.media,
    required this.busy,
    required this.onTap,
    this.onSave,
  });

  final GiphyMedia media;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy ? null : onTap,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              media.previewUrl,
              fit: BoxFit.cover,
              cacheWidth: 240,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) =>
                  const Center(child: Icon(Icons.broken_image_outlined)),
            ),
            if (busy)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (onSave != null)
              Align(
                alignment: Alignment.topRight,
                child: IconButton.filledTonal(
                  tooltip: 'Save to My stickers',
                  visualDensity: VisualDensity.compact,
                  onPressed: onSave,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 19),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LocalStickerTile extends StatefulWidget {
  const _LocalStickerTile({
    super.key,
    required this.sticker,
    required this.repository,
    required this.busy,
    required this.onTap,
    required this.onRemove,
  });

  final LocalSticker sticker;
  final LocalStickerPackRepository repository;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_LocalStickerTile> createState() => _LocalStickerTileState();
}

class _LocalStickerTileState extends State<_LocalStickerTile> {
  late final Future<Uint8List> _bytesFuture;
  Uint8List? _bytes;
  ImageProvider? _imageProvider;

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.repository.readBytes(widget.sticker);
  }

  @override
  void dispose() {
    final bytes = _bytes;
    final imageProvider = _imageProvider;
    if (imageProvider != null) unawaited(imageProvider.evict());
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          FutureBuilder<Uint8List>(
            future: _bytesFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Center(child: Icon(Icons.broken_image_outlined));
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              }
              _bytes = bytes;
              _imageProvider ??= MemoryImage(bytes);
              return InkWell(
                onTap: widget.busy ? null : widget.onTap,
                child: Image(
                  image: ResizeImage(_imageProvider!, width: 160),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Icon(Icons.broken_image_outlined)),
                ),
              );
            },
          ),
          if (widget.busy)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Remove sticker',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onRemove,
                icon: const Icon(Icons.close_rounded, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}
