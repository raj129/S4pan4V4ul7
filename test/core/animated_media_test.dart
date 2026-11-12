import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_vault/core/media/animated_media.dart';
import 'package:photo_vault/core/testing/repositories/in_memory_settings_repository.dart';
import 'package:photo_vault/features/chat/application/media/image_compressor.dart';

void main() {
  tearDown(() {
    HdrPreviewPreference.instance.resetForTesting();
  });

  test('detects GIF data independently of the filename', () {
    expect(isGif(Uint8List.fromList(ascii.encode('GIF89a'))), isTrue);
    expect(isGif(Uint8List.fromList(ascii.encode('GIF87a'))), isTrue);
    expect(isGif(Uint8List.fromList(ascii.encode('PNG89a'))), isFalse);
  });

  test('extracts the video segment from a Motion Photo JPEG', () {
    final mp4 = Uint8List.fromList([0, 0, 0, 12, ...ascii.encode('ftypmp42')]);
    final bytes = Uint8List.fromList([
      ...ascii.encode('jpeg xmp MicroVideoOffset="12"'),
      ...mp4,
    ]);

    expect(extractMotionPhotoVideo(bytes), orderedEquals(mp4));
  });

  test('detects HDR video transfer metadata', () {
    expect(isHdrVideo(Uint8List.fromList(ascii.encode('smpte2084'))), isTrue);
    expect(
      isHdrVideo(Uint8List.fromList(ascii.encode('plain video'))),
      isFalse,
    );
  });

  test(
    'detects Ultra HDR and HEIF photos and preserves their source bytes',
    () async {
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      final ultraHdr = Uint8List.fromList([...png, ...ascii.encode('hdrgm')]);
      final heif = Uint8List.fromList([
        0,
        0,
        0,
        16,
        ...ascii.encode('ftypheic'),
      ]);

      expect(isHdrImage(ultraHdr), isTrue);
      expect(isHdrImage(heif), isTrue);

      final prepared = await const ImageCompressor().prepare(
        bytes: ultraHdr,
        quality: ImageQuality.low,
      );
      expect(prepared.bytes, orderedEquals(ultraHdr));
    },
  );

  test(
    'persists animation playback mode for chat and vault previews',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings.media_animation_mode': 'once',
      });
      final preference = MediaAnimationPreference.instance;

      await preference.load();
      expect(preference.mode.value, MediaAnimationMode.once);

      await preference.setMode(MediaAnimationMode.loop);
      final stored = await SharedPreferences.getInstance();
      expect(stored.getString('settings.media_animation_mode'), 'loop');

      final settings = InMemorySettingsRepository();
      final hdrPreference = HdrPreviewPreference.instance..configure(settings);
      await hdrPreference.load();
      expect(hdrPreference.enabled.value, isTrue);
      await hdrPreference.setEnabled(false);
      expect(hdrPreference.enabled.value, isFalse);
      expect(await settings.isHdrPhotoPreviewEnabled(), isFalse);
      hdrPreference
        ..resetForTesting()
        ..configure(settings);
      await hdrPreference.load();
      expect(hdrPreference.enabled.value, isFalse);
    },
  );

  test('keeps animated GIF bytes unchanged at reduced image quality', () async {
    final bytes = Uint8List.fromList(
      base64Decode('R0lGODlhAQABAAD/ACwAAAAAAQABAAACADs='),
    );

    final prepared = await const ImageCompressor().prepare(
      bytes: bytes,
      quality: ImageQuality.low,
    );

    expect(prepared.bytes, orderedEquals(bytes));
  });
}
