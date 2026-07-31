import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/entities/chat_message.dart';

/// Renders a single chat message bubble with long-press delete options.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    required this.onDeleteForMe,
    this.onDeleteForEveryone,
  });

  final ChatMessage message;
  final bool isMine;
  final VoidCallback onDeleteForMe;
  final VoidCallback? onDeleteForEveryone;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bgColor = isMine ? cs.primary : cs.surfaceContainerHigh;
    final textColor = isMine ? cs.onPrimary : cs.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _showDeleteMenu(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(isMine ? 18 : 4),
              bottomRight: Radius.circular(isMine ? 4 : 18),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (message.isMedia) _MediaPreview(message: message),
              if (message.localDecryptedText != null &&
                  message.localDecryptedText!.isNotEmpty)
                Text(
                  message.localDecryptedText!,
                  style: TextStyle(color: textColor),
                ),
              const SizedBox(height: 4),
              Text(
                _formatTime(message.sentAt),
                style: TextStyle(
                  fontSize: 10,
                    color: textColor.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDeleteMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete for me'),
              onTap: () {
                Navigator.pop(context);
                onDeleteForMe();
              },
            ),
            if (onDeleteForEveryone != null)
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Delete for everyone'),
                onTap: () {
                  Navigator.pop(context);
                  onDeleteForEveryone!();
                },
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: const Text('Cancel'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) =>
      DateFormat.jm().format(dt.toLocal());
}

/// Placeholder for in-chat media preview.
/// Full decrypted preview is loaded lazily in a real implementation.
class _MediaPreview extends StatelessWidget {
  const _MediaPreview({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final icon = message.mediaType == MessageType.video
        ? Icons.videocam_outlined
        : Icons.image_outlined;
    return Container(
      width: 180,
      height: 120,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, size: 48, color: Colors.white70),
    );
  }
}
