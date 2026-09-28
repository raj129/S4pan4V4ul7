import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../crypto/services/chat_crypto_service.dart';
import '../../../domain/entities/chat_message.dart';
import '../../../domain/repositories/message_repository.dart';

/// Decrypts and caches chat media for display.
///
/// Attachments are stored encrypted, so every preview needs a download plus a
/// decrypt. Without a cache that work would repeat on each rebuild — and a
/// `ListView` rebuilds constantly while scrolling.
class ChatMediaLoader {
  ChatMediaLoader({required this.mediaRepository, required this.cryptoService});

  final MediaRepository mediaRepository;
  final ChatCryptoService cryptoService;

  final Map<String, Uint8List> _cache = {};
  final Map<String, Future<Uint8List>> _inFlight = {};

  /// Bounded so a long media-heavy thread cannot exhaust memory.
  static const _maxCachedItems = 40;

  Uint8List? cached(String storagePath) => _cache[storagePath];

  Future<Uint8List> load({
    required String threadId,
    required String storagePath,
  }) {
    final hit = _cache[storagePath];
    if (hit != null) return Future.value(hit);

    // Share one download between every widget asking for the same object.
    return _inFlight[storagePath] ??= _download(
      threadId,
      storagePath,
    ).whenComplete(() => _inFlight.remove(storagePath));
  }

  Future<Uint8List> _download(String threadId, String storagePath) async {
    final encrypted = await mediaRepository.downloadEncryptedMedia(storagePath);
    final plain = await cryptoService.decryptMedia(
      threadId: threadId,
      encryptedBytes: encrypted,
    );
    if (_cache.length >= _maxCachedItems) {
      _cache.remove(_cache.keys.first);
    }
    _cache[storagePath] = plain;
    return plain;
  }

  /// Download and decrypt without caching, for documents that are opened once
  /// and may be far larger than a thumbnail.
  Future<Uint8List> fetchUncached({
    required String threadId,
    required String storagePath,
  }) async {
    final hit = _cache[storagePath];
    if (hit != null) return hit;
    final encrypted = await mediaRepository.downloadEncryptedMedia(storagePath);
    return cryptoService.decryptMedia(
      threadId: threadId,
      encryptedBytes: encrypted,
    );
  }

  void clear() {
    _cache.clear();
    _inFlight.clear();
  }
}

/// Renders decrypted image/video attachments inside a bubble.
class ChatMediaPreview extends StatefulWidget {
  const ChatMediaPreview({
    super.key,
    required this.message,
    required this.loader,
    this.onTap,
  });

  final ChatMessage message;
  final ChatMediaLoader loader;
  final VoidCallback? onTap;

  @override
  State<ChatMediaPreview> createState() => _ChatMediaPreviewState();
}

class _ChatMediaPreviewState extends State<ChatMediaPreview> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  @override
  void didUpdateWidget(ChatMediaPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.mediaRef != widget.message.mediaRef) {
      _future = _start();
    }
  }

  Future<Uint8List> _start() => widget.loader.load(
    threadId: widget.message.threadId,
    storagePath: widget.message.mediaRef!,
  );

  @override
  Widget build(BuildContext context) {
    final meta = widget.message.mediaMeta;
    // Reserve the final size up front using the clear-text dimensions, so the
    // bubble does not jump when the decrypted image arrives.
    const width = 220.0;
    final height = (width / (meta?.aspectRatio ?? 4 / 3)).clamp(80.0, 320.0);

    return GestureDetector(
      onTap: widget.onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          height: height,
          child: FutureBuilder<Uint8List>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                );
              }
              if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                return const ColoredBox(
                  color: Colors.black26,
                  child: Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white70,
                      size: 36,
                    ),
                  ),
                );
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    snap.data!,
                    fit: BoxFit.cover,
                    // Videos have no decodable poster frame yet; show a
                    // neutral tile under the play button instead.
                    errorBuilder: (_, _, _) => const ColoredBox(
                      color: Colors.black54,
                      child: SizedBox.expand(),
                    ),
                  ),
                  if (widget.message.mediaType == MessageType.video)
                    const Center(
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.play_arrow, color: Colors.white),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Renders an encrypted document attachment and opens it on tap.
///
/// Opening needs a real file for the external viewer, so the decrypted bytes
/// are written to a private cache folder that is emptied before every open.
class ChatDocumentTile extends StatefulWidget {
  const ChatDocumentTile({
    super.key,
    required this.message,
    required this.loader,
    required this.textColor,
  });

  final ChatMessage message;
  final ChatMediaLoader loader;
  final Color textColor;

  @override
  State<ChatDocumentTile> createState() => _ChatDocumentTileState();
}

class _ChatDocumentTileState extends State<ChatDocumentTile> {
  bool _opening = false;

  static const _openDirName = 'chat_open';

  Future<void> _open() async {
    final ref = widget.message.mediaRef;
    if (ref == null || _opening) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _opening = true);
    try {
      final bytes = await widget.loader.fetchUncached(
        threadId: widget.message.threadId,
        storagePath: ref,
      );
      final tmp = await getTemporaryDirectory();
      final dir = Directory(p.join(tmp.path, _openDirName));
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, _safeName()));
      await file.writeAsBytes(bytes, flush: true);
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        messenger?.showSnackBar(
          SnackBar(content: Text('No app can open this file: ${result.message}')),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not open document: $e')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// A path-safe file name that keeps the original extension for the viewer.
  String _safeName() {
    final raw = widget.message.documentName ?? widget.message.messageId;
    final cleaned = p.basename(raw).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? widget.message.messageId : cleaned;
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.message.documentName ?? 'Document';
    final size = widget.message.mediaMeta?.readableSize ?? '';
    final color = widget.textColor;
    return InkWell(
      onTap: widget.message.mediaRef == null ? null : _open,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 36,
              child: _opening
                  ? const Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(Icons.insert_drive_file_rounded, color: color, size: 32),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontWeight: FontWeight.w600),
                  ),
                  if (size.isNotEmpty)
                    Text(
                      size,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
