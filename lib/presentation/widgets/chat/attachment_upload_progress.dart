import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/chat/media_send_status.dart';

/// One transfer surface shared by image, video, audio and document bubbles.
class AttachmentUploadProgress extends StatefulWidget {
  const AttachmentUploadProgress({
    super.key,
    required this.status,
    this.onPause,
    this.onResume,
    this.onRetry,
    this.onCancel,
  });

  final MediaSendStatus status;
  final FutureOr<void> Function()? onPause;
  final FutureOr<void> Function()? onResume;
  final FutureOr<void> Function()? onRetry;
  final FutureOr<void> Function()? onCancel;

  @override
  State<AttachmentUploadProgress> createState() =>
      _AttachmentUploadProgressState();
}

class _AttachmentUploadProgressState extends State<AttachmentUploadProgress> {
  bool _busy = false;

  Future<void> _act(FutureOr<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Upload action failed. Please retry.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _size(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB'
      : bytes >= 1024
      ? '${(bytes / 1024).toStringAsFixed(1)} KB'
      : '$bytes B';

  Widget _action(
    String label,
    IconData icon,
    FutureOr<void> Function()? action,
  ) => TextButton.icon(
    onPressed: _busy || action == null ? null : () => _act(action),
    icon: Icon(icon, size: 18),
    label: Text(label),
  );

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final state = status.lifecycle;
    final total = status.totalBytes;
    final measured =
        total != null && total > 0 && status.processedBytes != null;
    final terminal =
        state == MediaUploadLifecycle.completed ||
        state == MediaUploadLifecycle.cancelled;
    return SizedBox(
      width: 260,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status.label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: status.isIndeterminate ? null : status.progress,
              semanticsLabel: status.label,
            ),
            if (measured) ...[
              const SizedBox(height: 6),
              Text(
                '${_size(status.processedBytes!)} / ${_size(total)}'
                ' · ${(status.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
              ),
            ],
            if (!terminal)
              Wrap(
                children: [
                  if (state == MediaUploadLifecycle.paused)
                    _action('Resume', Icons.play_arrow, widget.onResume)
                  else if (state == MediaUploadLifecycle.failed)
                    _action('Retry', Icons.refresh, widget.onRetry)
                  else if (state != null)
                    _action('Pause', Icons.pause, widget.onPause),
                  _action('Cancel', Icons.close, widget.onCancel),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
