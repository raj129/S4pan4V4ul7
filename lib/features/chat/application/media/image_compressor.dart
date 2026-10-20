import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How much an outgoing photo is downscaled before it is encrypted and sent.
enum ImageQuality { original, high, medium, low }

extension ImageQualityX on ImageQuality {
  String get label => switch (this) {
    ImageQuality.original => 'Original',
    ImageQuality.high => 'High',
    ImageQuality.medium => 'Medium',
    ImageQuality.low => 'Low',
  };

  String get description => switch (this) {
    ImageQuality.original => 'Full resolution, largest upload',
    ImageQuality.high => 'Up to 1920 px',
    ImageQuality.medium => 'Up to 1280 px',
    ImageQuality.low => 'Up to 800 px, smallest upload',
  };

  /// Longest edge in pixels, or null to keep the original size.
  int? get maxDimension => switch (this) {
    ImageQuality.original => null,
    ImageQuality.high => 1920,
    ImageQuality.medium => 1280,
    ImageQuality.low => 800,
  };

  int get jpegQuality => switch (this) {
    ImageQuality.original => 95,
    ImageQuality.high => 85,
    ImageQuality.medium => 75,
    ImageQuality.low => 60,
  };

  static ImageQuality parse(String? name) {
    for (final q in ImageQuality.values) {
      if (q.name == name) return q;
    }
    return ImageQuality.high;
  }
}

/// An image prepared for sending: the payload plus its small preview.
class PreparedImage {
  const PreparedImage({
    required this.bytes,
    required this.thumbnail,
    required this.width,
    required this.height,
  });

  /// Full-size (possibly downscaled) image to upload.
  final Uint8List bytes;

  /// Small preview uploaded alongside it, so listing a thread does not have to
  /// download the full image for every bubble.
  final Uint8List thumbnail;

  final int width;
  final int height;
}

/// Resizes outgoing photos and builds their previews.
///
/// Decoding a photo is CPU-bound and would jank the UI, so the work runs in a
/// background isolate. The bytes are plaintext here; encryption happens
/// afterwards, and nothing is written to disk in between.
class ImageCompressor {
  const ImageCompressor();

  /// Longest edge of the generated preview.
  static const thumbnailMaxDimension = 320;
  static const thumbnailQuality = 70;

  Future<PreparedImage> prepare({
    required Uint8List bytes,
    required ImageQuality quality,
  }) {
    final maxDimension = quality.maxDimension;
    final jpegQuality = quality.jpegQuality;
    return Isolate.run(() => _prepare(bytes, maxDimension, jpegQuality));
  }

  /// Estimated upload size for [bytes] at [quality], for the picker sheet.
  Future<int> estimateSize({
    required Uint8List bytes,
    required ImageQuality quality,
  }) async {
    final prepared = await prepare(bytes: bytes, quality: quality);
    return prepared.bytes.length;
  }
}

PreparedImage _prepare(Uint8List bytes, int? maxDimension, int jpegQuality) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    // Not a decodable image (an unusual format, or already corrupt). Send it
    // untouched rather than failing the whole attachment.
    return PreparedImage(
      bytes: bytes,
      thumbnail: Uint8List(0),
      width: 0,
      height: 0,
    );
  }
  final normalized = img.bakeOrientation(decoded);

  var payload = bytes;
  var width = normalized.width;
  var height = normalized.height;

  if (maxDimension != null) {
    final resized = _resize(normalized, maxDimension);
    final encoded = Uint8List.fromList(
      img.encodeJpg(resized, quality: jpegQuality),
    );
    // Re-encoding a small or already-compressed photo can grow it; in that
    // case the original is the better upload.
    if (encoded.length < bytes.length) {
      payload = encoded;
      width = resized.width;
      height = resized.height;
    }
  }

  final thumb = _resize(normalized, ImageCompressor.thumbnailMaxDimension);
  final thumbnail = Uint8List.fromList(
    img.encodeJpg(thumb, quality: ImageCompressor.thumbnailQuality),
  );

  return PreparedImage(
    bytes: payload,
    thumbnail: thumbnail,
    width: width,
    height: height,
  );
}

img.Image _resize(img.Image source, int maxDimension) {
  final longest = source.width >= source.height ? source.width : source.height;
  if (longest <= maxDimension) return source;
  return img.copyResize(
    source,
    width: source.width >= source.height ? maxDimension : null,
    height: source.height > source.width ? maxDimension : null,
    interpolation: img.Interpolation.average,
  );
}
