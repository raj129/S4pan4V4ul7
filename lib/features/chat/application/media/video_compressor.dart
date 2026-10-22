import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';

/// How much an outgoing video is compressed/downscaled before encryption and upload.
enum VideoQuality { original, high, medium, low }

extension VideoQualityX on VideoQuality {
  String get label => switch (this) {
    VideoQuality.original => 'Original',
    VideoQuality.high => 'High (1080p)',
    VideoQuality.medium => 'Medium (720p)',
    VideoQuality.low => 'Low (480p)',
  };

  String get description => switch (this) {
    VideoQuality.original => 'Original quality, largest upload',
    VideoQuality.high => '1080p, up to ~2.5 Mbps',
    VideoQuality.medium => '720p, up to ~1.2 Mbps',
    VideoQuality.low => '480p, smallest upload (~600 kbps)',
  };

  int? get targetHeight => switch (this) {
    VideoQuality.original => null,
    VideoQuality.high => 1080,
    VideoQuality.medium => 720,
    VideoQuality.low => 480,
  };

  int? get targetBitrate => switch (this) {
    VideoQuality.original => null,
    VideoQuality.high => 2500000,
    VideoQuality.medium => 1200000,
    VideoQuality.low => 600000,
  };

  static VideoQuality parse(String? name) {
    for (final q in VideoQuality.values) {
      if (q.name == name) return q;
    }
    return VideoQuality.high;
  }
}

/// Metadata and extracted preview thumbnail for a video.
class VideoMetadata {
  const VideoMetadata({
    required this.width,
    required this.height,
    required this.durationMs,
    required this.thumbnail,
  });

  final int width;
  final int height;
  final int durationMs;
  final Uint8List thumbnail;
}

/// A video prepared for encrypted sending: payload plus thumbnail.
class PreparedVideo {
  const PreparedVideo({
    required this.bytes,
    required this.thumbnail,
    required this.width,
    required this.height,
    required this.durationMs,
  });

  final Uint8List bytes;
  final Uint8List thumbnail;
  final int width;
  final int height;
  final int durationMs;
}

/// Manages video metadata extraction, thumbnail generation, and quality transcoding.
class VideoCompressor {
  const VideoCompressor({
    MethodChannel channel = const MethodChannel(
      'photo_vault/chat_secure_media',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  /// Extract metadata (width, height, duration) and a JPEG preview thumbnail.
  Future<VideoMetadata> extractMetadata(Uint8List bytes) async {
    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'extractVideoMetadata',
        {'bytes': bytes},
      );
      if (result != null) {
        final thumbBytes = result['thumbnail'] as Uint8List?;
        return VideoMetadata(
          width: (result['width'] as num?)?.toInt() ?? 0,
          height: (result['height'] as num?)?.toInt() ?? 0,
          durationMs: (result['durationMs'] as num?)?.toInt() ?? 0,
          thumbnail: thumbBytes ?? Uint8List(0),
        );
      }
    } catch (_) {
      // Platform channel unavailable or unhandled format
    }
    return VideoMetadata(
      width: 0,
      height: 0,
      durationMs: 0,
      thumbnail: Uint8List(0),
    );
  }

  /// Prepares the video for sending according to [quality].
  /// If transcoding is not requested or fails, returns original bytes with extracted thumbnail.
  Future<PreparedVideo> prepare({
    required Uint8List bytes,
    required VideoQuality quality,
  }) async {
    final meta = await extractMetadata(bytes);

    if (quality == VideoQuality.original || quality.targetHeight == null) {
      return PreparedVideo(
        bytes: bytes,
        thumbnail: meta.thumbnail,
        width: meta.width,
        height: meta.height,
        durationMs: meta.durationMs,
      );
    }

    try {
      final result = await _channel.invokeMapMethod<Object?, Object?>(
        'compressVideo',
        {
          'bytes': bytes,
          'targetHeight': quality.targetHeight,
          'targetBitrate': quality.targetBitrate,
        },
      );
      if (result != null) {
        final compressedBytes = result['bytes'] as Uint8List?;
        if (compressedBytes != null &&
            compressedBytes.isNotEmpty &&
            compressedBytes.length < bytes.length) {
          final newWidth = (result['width'] as num?)?.toInt() ?? meta.width;
          final newHeight = (result['height'] as num?)?.toInt() ?? meta.height;
          final newThumb = result['thumbnail'] as Uint8List? ?? meta.thumbnail;
          return PreparedVideo(
            bytes: compressedBytes,
            thumbnail: newThumb,
            width: newWidth,
            height: newHeight,
            durationMs: meta.durationMs,
          );
        }
      }
    } catch (_) {
      // Fallback to original bytes on transcoding error
    }

    return PreparedVideo(
      bytes: bytes,
      thumbnail: meta.thumbnail,
      width: meta.width,
      height: meta.height,
      durationMs: meta.durationMs,
    );
  }

  /// Estimates output sizes for each quality option given original byte length and duration.
  Map<VideoQuality, int> estimateAllSizes({
    required int originalBytes,
    int? durationMs,
  }) {
    final result = <VideoQuality, int>{
      VideoQuality.original: originalBytes,
    };

    final durationSec = (durationMs != null && durationMs > 0)
        ? durationMs / 1000.0
        : null;

    for (final q in [VideoQuality.high, VideoQuality.medium, VideoQuality.low]) {
      if (durationSec != null && q.targetBitrate != null) {
        final estimatedBytes = ((q.targetBitrate! * durationSec) / 8).round();
        // Capped so compression estimate never exceeds original size
        result[q] = min(originalBytes, max(1024, estimatedBytes));
      } else {
        final factor = switch (q) {
          VideoQuality.high => 0.65,
          VideoQuality.medium => 0.40,
          VideoQuality.low => 0.20,
          VideoQuality.original => 1.0,
        };
        result[q] = (originalBytes * factor).round();
      }
    }

    return result;
  }
}
