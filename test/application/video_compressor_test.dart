import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:photo_vault/application/services/video_compressor.dart';

void main() {
  test('quality parsing defaults safely and recognizes saved values', () {
    expect(ChatVideoQualityX.parse(null), ChatVideoQuality.high);
    expect(ChatVideoQualityX.parse('invalid'), ChatVideoQuality.high);
    expect(ChatVideoQualityX.parse('low'), ChatVideoQuality.low);
  });

  test('Original returns source bytes unchanged', () async {
    final directory = await Directory.systemTemp.createTemp('video-test-');
    try {
      final source = File(p.join(directory.path, 'source.mp4'));
      final bytes = Uint8List.fromList([0, 1, 2, 3]);
      await source.writeAsBytes(bytes);

      final prepared = await const VideoCompressor().prepare(
        path: source.path,
        quality: ChatVideoQuality.original,
      );

      expect(prepared.bytes, bytes);
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'compressed quality reports unsupported platforms rather than sending original',
    () async {
      if (VideoCompressor.isSupported) return;
      final directory = await Directory.systemTemp.createTemp('video-test-');
      try {
        final source = File(p.join(directory.path, 'source.mp4'));
        await source.writeAsBytes([0, 1, 2, 3]);

        await expectLater(
          const VideoCompressor().prepare(
            path: source.path,
            quality: ChatVideoQuality.high,
          ),
          throwsUnsupportedError,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
