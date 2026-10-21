import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/video_compressor.dart';

void main() {
  group('VideoQuality', () {
    test('parses quality names correctly with fallback', () {
      expect(VideoQualityX.parse('original'), VideoQuality.original);
      expect(VideoQualityX.parse('high'), VideoQuality.high);
      expect(VideoQualityX.parse('medium'), VideoQuality.medium);
      expect(VideoQualityX.parse('low'), VideoQuality.low);
      expect(VideoQualityX.parse('unknown'), VideoQuality.high);
      expect(VideoQualityX.parse(null), VideoQuality.high);
    });

    test('attributes define appropriate heights and bitrates', () {
      expect(VideoQuality.original.targetHeight, isNull);
      expect(VideoQuality.original.targetBitrate, isNull);

      expect(VideoQuality.high.targetHeight, 1080);
      expect(VideoQuality.high.targetBitrate, 2500000);

      expect(VideoQuality.medium.targetHeight, 720);
      expect(VideoQuality.medium.targetBitrate, 1200000);

      expect(VideoQuality.low.targetHeight, 480);
      expect(VideoQuality.low.targetBitrate, 600000);
    });
  });

  group('VideoCompressor size estimation', () {
    const compressor = VideoCompressor();

    test('estimates sizes accurately with duration', () {
      // 10-second video of 20MB original size
      const originalBytes = 20 * 1024 * 1024;
      const durationMs = 10000;

      final estimates = compressor.estimateAllSizes(
        originalBytes: originalBytes,
        durationMs: durationMs,
      );

      expect(estimates[VideoQuality.original], originalBytes);
      // High: 2.5 Mbps * 10s / 8 = 3,125,000 bytes
      expect(estimates[VideoQuality.high], closeTo(3125000, 1000));
      // Medium: 1.2 Mbps * 10s / 8 = 1,500,000 bytes
      expect(estimates[VideoQuality.medium], closeTo(1500000, 1000));
      // Low: 0.6 Mbps * 10s / 8 = 750,000 bytes
      expect(estimates[VideoQuality.low], closeTo(750000, 1000));

      // Each quality should be smaller than the higher one
      expect(estimates[VideoQuality.high]!, lessThan(originalBytes));
      expect(estimates[VideoQuality.medium]!, lessThan(estimates[VideoQuality.high]!));
      expect(estimates[VideoQuality.low]!, lessThan(estimates[VideoQuality.medium]!));
    });

    test('estimates fallback to proportional factors when duration is null', () {
      const originalBytes = 10 * 1024 * 1024;

      final estimates = compressor.estimateAllSizes(
        originalBytes: originalBytes,
      );

      expect(estimates[VideoQuality.original], originalBytes);
      expect(estimates[VideoQuality.high], (originalBytes * 0.65).round());
      expect(estimates[VideoQuality.medium], (originalBytes * 0.40).round());
      expect(estimates[VideoQuality.low], (originalBytes * 0.20).round());
    });

    test('fallback returns original bytes if channel fails', () async {
      final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final prepared = await compressor.prepare(
        bytes: dummyBytes,
        quality: VideoQuality.original,
      );

      expect(prepared.bytes, dummyBytes);
      expect(prepared.thumbnail, isEmpty);
      expect(prepared.width, 0);
      expect(prepared.height, 0);
    });
  });
}
