import 'dart:typed_data';

import 'package:flutter/material.dart';

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
    return _inFlight[storagePath] ??= _download(threadId, storagePath)
        .whenComplete(() => _inFlight.remove(storagePath));
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
                  Image.memory(snap.data!, fit: BoxFit.cover),
                  if (widget.message.mediaType == MessageType.video)
                    const Center(
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                        ),
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
