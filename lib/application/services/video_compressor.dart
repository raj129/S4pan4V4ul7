import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_compress/video_compress.dart' as native;

enum ChatVideoQuality { original, high, medium, low }

extension ChatVideoQualityX on ChatVideoQuality {
  String get label => switch (this) {
    ChatVideoQuality.original => 'Original',
    ChatVideoQuality.high => 'High',
    ChatVideoQuality.medium => 'Medium',
    ChatVideoQuality.low => 'Low',
  };

  String get description => switch (this) {
    ChatVideoQuality.original => 'Keep the source unchanged',
    ChatVideoQuality.high => 'Up to 1080p',
    ChatVideoQuality.medium => 'Up to 720p',
    ChatVideoQuality.low => 'Up to 540p, smallest upload',
  };

  native.VideoQuality get nativeQuality => switch (this) {
    ChatVideoQuality.original => native.VideoQuality.HighestQuality,
    ChatVideoQuality.high => native.VideoQuality.Res1920x1080Quality,
    ChatVideoQuality.medium => native.VideoQuality.Res1280x720Quality,
    ChatVideoQuality.low => native.VideoQuality.Res960x540Quality,
  };

  static ChatVideoQuality parse(String? name) {
    for (final quality in ChatVideoQuality.values) {
      if (quality.name == name) return quality;
    }
    return ChatVideoQuality.high;
  }
}

class PreparedVideo {
  const PreparedVideo({
    required this.bytes,
    this.width,
    this.height,
    this.durationMs,
  });

  final Uint8List bytes;
  final int? width;
  final int? height;
  final int? durationMs;
}

class VideoCompressionException implements Exception {
  const VideoCompressionException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// File-based video transcoding. The plugin's temporary output is removed
/// after its encrypted upload bytes have been prepared.
class VideoCompressor {
  const VideoCompressor();

  static bool get isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  static Future<void> cleanStaleOutputs() async {
    if (isSupported) await native.VideoCompress.deleteAllCache();
  }

  Future<void> cancelCompression() async {
    if (isSupported) await native.VideoCompress.cancelCompression();
  }

  Future<PreparedVideo> prepare({
    required String path,
    required ChatVideoQuality quality,
    void Function(double progress)? onProgress,
    int maxOutputBytes = 64 * 1024 * 1024 - 1024,
  }) async {
    final source = File(path);
    if (!await source.exists()) {
      throw const VideoCompressionException(
        'The selected video is unavailable.',
      );
    }
    final originalSize = await source.length();

    if (quality == ChatVideoQuality.original) {
      if (originalSize > maxOutputBytes) {
        throw const VideoCompressionException(
          'Original videos must be smaller than 64 MB.',
        );
      }
      return PreparedVideo(bytes: await source.readAsBytes());
    }
    if (!isSupported) {
      throw UnsupportedError('Video compression is not supported here.');
    }

    final subscription = native.VideoCompress.compressProgress$.subscribe(
      (progress) => onProgress?.call((progress / 100).clamp(0.0, 1.0)),
    );
    String? outputPath;
    try {
      final info = await native.VideoCompress.compressVideo(
        path,
        quality: quality.nativeQuality,
        deleteOrigin: false,
      );
      outputPath = info?.path;
      if (info == null || outputPath == null || info.isCancel == true) {
        throw const VideoCompressionException(
          'Video compression did not complete.',
        );
      }

      final output = File(outputPath);
      if (!await output.exists()) {
        throw const VideoCompressionException(
          'The compressed video could not be found.',
        );
      }
      final outputSize = await output.length();
      if (outputSize > maxOutputBytes &&
          (outputSize < originalSize || originalSize > maxOutputBytes)) {
        throw const VideoCompressionException(
          'Compressed video is still larger than 64 MB.',
        );
      }
      final bytes = outputSize < originalSize
          ? await output.readAsBytes()
          : await source.readAsBytes();
      if (bytes.isEmpty) {
        throw const VideoCompressionException('The prepared video is empty.');
      }
      return PreparedVideo(
        bytes: bytes,
        width: info.width,
        height: info.height,
        durationMs: info.duration?.round(),
      );
    } finally {
      subscription.unsubscribe();
      if (outputPath != null && outputPath != path) {
        final output = File(outputPath);
        if (await output.exists()) await output.delete();
      }
    }
  }
}
