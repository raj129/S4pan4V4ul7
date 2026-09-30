import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photo_vault/application/services/profile_service.dart';

void main() {
  test('a large noisy photo is compressed to a small square JPEG', () {
    final rnd = Random(1);
    final big = img.Image(width: 1600, height: 1200);
    for (final p in big) {
      p.setRgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
    }
    final input = Uint8List.fromList(img.encodeJpg(big, quality: 95));

    final out = compressAvatar(input);
    final decoded = img.decodeJpg(out)!;
    expect(decoded.width, ProfileService.avatarSize);
    expect(decoded.height, ProfileService.avatarSize);
    expect(out.length, lessThanOrEqualTo(maxAvatarBytes));
    expect(out.length, lessThan(input.length));
  });

  test('undecodable bytes are rejected', () {
    expect(
      () => compressAvatar(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
