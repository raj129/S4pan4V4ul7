import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/application/services/image_compressor.dart';

void main() {
  const compressor = ImageCompressor();

  /// A noisy image, so JPEG cannot compress it to almost nothing and the
  /// size comparisons stay meaningful.
  img.Image noisy(int width, int height) {
    final random = Random(42);
    final image = img.Image(width: width, height: height);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        image.setPixelRgb(
          x,
          y,
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
    }
    return image;
  }

  test('downscales to the quality ceiling and keeps the aspect ratio', () async {
    final png = img.encodePng(noisy(2000, 1000));

    final prepared = await compressor.prepare(
      bytes: png,
      quality: ImageQuality.medium,
    );

    expect(prepared.width, 1280);
    expect(prepared.height, 640);
    expect(prepared.bytes.length, lessThan(png.length));
  });

  test('a lower quality produces a smaller upload', () async {
    final png = img.encodePng(noisy(2000, 1000));

    final high = await compressor.prepare(
      bytes: png,
      quality: ImageQuality.high,
    );
    final low = await compressor.prepare(bytes: png, quality: ImageQuality.low);

    expect(low.bytes.length, lessThan(high.bytes.length));
  });

  test('the preview is capped at the thumbnail size', () async {
    final png = img.encodePng(noisy(2000, 1000));

    final prepared = await compressor.prepare(
      bytes: png,
      quality: ImageQuality.original,
    );

    final thumb = img.decodeImage(prepared.thumbnail)!;
    expect(thumb.width, ImageCompressor.thumbnailMaxDimension);
    expect(thumb.height, 160);
    expect(prepared.thumbnail.length, lessThan(prepared.bytes.length));
  });

  test('original quality keeps the source bytes untouched', () async {
    final png = img.encodePng(noisy(400, 300));

    final prepared = await compressor.prepare(
      bytes: png,
      quality: ImageQuality.original,
    );

    expect(prepared.bytes, png);
    expect(prepared.width, 400);
    expect(prepared.height, 300);
  });

  test('a small image is not re-encoded into something larger', () async {
    final png = img.encodePng(img.Image(width: 8, height: 8));

    final prepared = await compressor.prepare(
      bytes: png,
      quality: ImageQuality.low,
    );

    expect(prepared.bytes.length, lessThanOrEqualTo(png.length));
  });

  test('undecodable bytes are passed through rather than failing', () async {
    final garbage = Uint8List.fromList(List<int>.filled(64, 7));

    final prepared = await compressor.prepare(
      bytes: garbage,
      quality: ImageQuality.high,
    );

    expect(prepared.bytes.length, 64);
    expect(prepared.thumbnail, isEmpty);
  });

  test('an unknown stored name falls back to a sensible quality', () {
    expect(ImageQualityX.parse(null), ImageQuality.high);
    expect(ImageQualityX.parse('nonsense'), ImageQuality.high);
    expect(ImageQualityX.parse('low'), ImageQuality.low);
  });
}
