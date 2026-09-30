import 'package:flutter/material.dart';

import '../../../application/services/image_compressor.dart';

/// Lets the sender trade image quality for upload size before a photo is sent.
class ImageQualitySheet extends StatelessWidget {
  const ImageQualitySheet({
    super.key,
    required this.originalBytes,
    required this.selected,
  });

  /// Size of the picked photo, used to show what each option saves.
  final int originalBytes;
  final ImageQuality selected;

  static Future<ImageQuality?> show(
    BuildContext context, {
    required int originalBytes,
    required ImageQuality selected,
  }) {
    return showModalBottomSheet<ImageQuality>(
      context: context,
      builder: (_) =>
          ImageQualitySheet(originalBytes: originalBytes, selected: selected),
    );
  }

  /// Rough size guide. A real estimate would mean compressing at every level,
  /// which costs far more than the hint is worth.
  String _estimate(ImageQuality quality) {
    if (quality == ImageQuality.original) return _readable(originalBytes);
    final factor = switch (quality) {
      ImageQuality.high => 0.45,
      ImageQuality.medium => 0.25,
      ImageQuality.low => 0.12,
      ImageQuality.original => 1.0,
    };
    final estimated = (originalBytes * factor).round();
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
                'Send photo as',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
              ),
            ),
            // Plain tiles rather than radios: a radio ignores a tap on the
            // option that is already selected, which would silently drop the
            // send.
            for (final quality in ImageQuality.values)
              ListTile(
                leading: Icon(
                  quality == selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: quality == selected ? theme.colorScheme.primary : null,
                ),
                title: Text(quality.label),
                subtitle: Text('${quality.description} · ${_estimate(quality)}'),
                onTap: () => Navigator.pop(context, quality),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
