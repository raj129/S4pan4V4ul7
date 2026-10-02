import 'package:flutter/material.dart';

import '../../../application/services/video_compressor.dart';

class VideoQualitySheet extends StatelessWidget {
  const VideoQualitySheet({
    super.key,
    required this.selected,
    required this.originalBytes,
    this.allowCompression = true,
  });

  final ChatVideoQuality selected;
  final int originalBytes;
  final bool allowCompression;

  static Future<ChatVideoQuality?> show(
    BuildContext context, {
    required ChatVideoQuality selected,
    required int originalBytes,
    bool allowCompression = true,
  }) {
    return showModalBottomSheet<ChatVideoQuality>(
      context: context,
      builder: (_) => VideoQualitySheet(
        selected: selected,
        originalBytes: originalBytes,
        allowCompression: allowCompression,
      ),
    );
  }

  static String _readable(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Send video as',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            for (final quality in [
              ChatVideoQuality.original,
              if (allowCompression) ...ChatVideoQuality.values.skip(1),
            ])
              ListTile(
                leading: Icon(
                  quality == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: quality == selected ? theme.colorScheme.primary : null,
                ),
                title: Text(quality.label),
                subtitle: Text(
                  quality == ChatVideoQuality.original
                      ? '${quality.description} · ${_readable(originalBytes)}'
                      : quality.description,
                ),
                onTap: () => Navigator.pop(context, quality),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
