import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../application/media/video_compressor.dart';

/// Lets the sender trade video quality and resolution for upload size before sending.
class VideoQualitySheet extends StatefulWidget {
  const VideoQualitySheet({
    super.key,
    required this.originalBytes,
    required this.selected,
    this.videoBytes,
    this.initialDurationMs,
    this.initialEstimates,
  });

  /// Size of the picked video in bytes.
  final int originalBytes;
  final VideoQuality selected;
  final Uint8List? videoBytes;
  final int? initialDurationMs;
  final Map<VideoQuality, int>? initialEstimates;

  static Future<VideoQuality?> show(
    BuildContext context, {
    required int originalBytes,
    required VideoQuality selected,
    Uint8List? videoBytes,
    int? initialDurationMs,
    Map<VideoQuality, int>? initialEstimates,
  }) {
    return showModalBottomSheet<VideoQuality>(
      context: context,
      builder: (_) => VideoQualitySheet(
        originalBytes: originalBytes,
        selected: selected,
        videoBytes: videoBytes,
        initialDurationMs: initialDurationMs,
        initialEstimates: initialEstimates,
      ),
    );
  }

  @override
  State<VideoQualitySheet> createState() => _VideoQualitySheetState();
}

class _VideoQualitySheetState extends State<VideoQualitySheet> {
  Map<VideoQuality, int>? _estimates;
  int? _durationMs;

  @override
  void initState() {
    super.initState();
    _durationMs = widget.initialDurationMs;
    _estimates = widget.initialEstimates;

    if (_estimates == null) {
      _estimates = const VideoCompressor().estimateAllSizes(
        originalBytes: widget.originalBytes,
        durationMs: _durationMs,
      );
    }

    if (_durationMs == null && widget.videoBytes != null) {
      const VideoCompressor().extractMetadata(widget.videoBytes!).then((meta) {
        if (mounted && meta.durationMs > 0) {
          setState(() {
            _durationMs = meta.durationMs;
            _estimates = const VideoCompressor().estimateAllSizes(
              originalBytes: widget.originalBytes,
              durationMs: meta.durationMs,
            );
          });
        }
      });
    }
  }

  String _estimate(VideoQuality quality) {
    if (_estimates != null && _estimates!.containsKey(quality)) {
      final bytes = _estimates![quality]!;
      return _readable(bytes);
    }
    if (quality == VideoQuality.original) {
      return _readable(widget.originalBytes);
    }
    final factor = switch (quality) {
      VideoQuality.high => 0.65,
      VideoQuality.medium => 0.40,
      VideoQuality.low => 0.20,
      VideoQuality.original => 1.0,
    };
    final estimated = (widget.originalBytes * factor).round();
    return '≈ ${_readable(estimated)}';
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
            for (final quality in VideoQuality.values)
              ListTile(
                leading: Icon(
                  quality == widget.selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: quality == widget.selected
                      ? theme.colorScheme.primary
                      : null,
                ),
                title: Text(quality.label),
                subtitle: Text(
                  '${quality.description} · ${_estimate(quality)}',
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
