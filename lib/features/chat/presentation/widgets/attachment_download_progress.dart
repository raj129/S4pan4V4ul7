import 'dart:async';
import 'package:flutter/material.dart';

import '../../application/media/chat_media_loader.dart';
import 'attachment_upload_progress.dart';
import '../../application/media/media_send_status.dart';

class AttachmentDownloadProgress extends StatelessWidget {
  const AttachmentDownloadProgress({
    super.key,
    required this.loader,
    required this.storagePath,
    this.onRetry,
  });
  final ChatMediaLoader loader;
  final String storagePath;
  final FutureOr<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final downloads = loader.downloads;
    return AnimatedBuilder(
      animation: downloads == null
          ? loader
          : Listenable.merge([loader, downloads]),
      builder: (context, _) {
        final job = downloads?.job(storagePath);
        final stage = loader.stage(storagePath) ?? 'Loading attachment…';
        if (loader.isSent(storagePath) ||
            job == null ||
            (stage != 'Downloading attachment…' &&
                job.state != MediaUploadLifecycle.paused &&
                job.state != MediaUploadLifecycle.failed &&
                job.state != MediaUploadLifecycle.cancelled)) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    stage,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AttachmentUploadProgress(
              status: job.progress,
              label: job.label,
              actionError: 'Download action failed. Please retry.',
              retryCancelled: onRetry != null,
              onPause: () => downloads!.command(storagePath, 'pause'),
              onResume: () => downloads!.command(storagePath, 'resume'),
              onRetry: () async {
                await downloads!.command(storagePath, 'retry');
                await onRetry?.call();
              },
              onCancel: () => downloads!.command(storagePath, 'cancel'),
            ),
            if (job.error?.isNotEmpty == true) Text(job.error!),
          ],
        );
      },
    );
  }
}
