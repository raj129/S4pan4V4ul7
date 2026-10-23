import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/media/media_send_status.dart';

/// One transfer surface shared by image, video, audio and document bubbles.
class AttachmentUploadProgress extends StatefulWidget {
  const AttachmentUploadProgress({
    super.key,
    required this.status,
    this.onPause,
    this.onResume,
    this.onRetry,
    this.onCancel,
    this.label,
    this.actionError = 'Upload action failed. Please retry.',
    this.retryCancelled = false,
  });

  final MediaSendStatus status;
  final String? label;
  final String actionError;
  final bool retryCancelled;
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(widget.actionError)));
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
  ) => Padding(
    padding: const EdgeInsets.only(right: 6, top: 4),
    child: TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      ),
      onPressed: _busy || action == null ? null : () => _act(action),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
    ),
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
    final cs = Theme.of(context).colorScheme;

    final progressColor = state == MediaUploadLifecycle.failed
        ? cs.error
        : state == MediaUploadLifecycle.paused
        ? cs.tertiary
        : cs.primary;

    final stateIcon = state == MediaUploadLifecycle.failed
        ? Icons.error_outline_rounded
        : state == MediaUploadLifecycle.paused
        ? Icons.pause_circle_outline_rounded
        : state == MediaUploadLifecycle.completed
        ? Icons.check_circle_outline_rounded
        : Icons.cloud_sync_outlined;

    return Container(
      width: 270,
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(stateIcon, size: 18, color: progressColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label ?? status.label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: status.isIndeterminate ? null : status.progress,
              semanticsLabel: widget.label ?? status.label,
              color: progressColor,
              backgroundColor: progressColor.withValues(alpha: 0.18),
            ),
          ),
          if (measured) ...[
            const SizedBox(height: 6),
            Text(
              '${_size(status.processedBytes!)} / ${_size(total)}'
              ' · ${(status.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (!terminal) ...[
            const SizedBox(height: 4),
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
          if (state == MediaUploadLifecycle.cancelled &&
              widget.retryCancelled) ...[
            const SizedBox(height: 4),
            _action('Retry download', Icons.refresh, widget.onRetry),
          ],
        ],
      ),
    );
  }
}
