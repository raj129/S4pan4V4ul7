import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/vault/domain/repositories/settings_repository.dart';

enum MediaAnimationMode { loop, once }

class MediaAnimationPreference {
  MediaAnimationPreference._();

  static final instance = MediaAnimationPreference._();
  static const _preferenceKey = 'settings.media_animation_mode';

  final mode = ValueNotifier<MediaAnimationMode>(MediaAnimationMode.loop);
  Future<void>? _load;
  bool _hasExplicitMode = false;

  Future<void> load() => _load ??= _loadSavedMode();

  Future<void> _loadSavedMode() async {
    final preferences = await SharedPreferences.getInstance();
    if (_hasExplicitMode) return;
    mode.value = switch (preferences.getString(_preferenceKey)) {
      'once' => MediaAnimationMode.once,
      _ => MediaAnimationMode.loop,
    };
  }

  @visibleForTesting
  void resetForTesting() {
    _load = null;
    _hasExplicitMode = false;
    mode.value = MediaAnimationMode.loop;
  }

  Future<void> setMode(MediaAnimationMode next) async {
    final previous = mode.value;
    _hasExplicitMode = true;
    mode.value = next;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_preferenceKey, next.name);
    } catch (_) {
      mode.value = previous;
      rethrow;
    }
  }

  Future<void> toggle() async {
    await load();
    await setMode(
      mode.value == MediaAnimationMode.loop
          ? MediaAnimationMode.once
          : MediaAnimationMode.loop,
    );
  }
}

class HdrPreviewPreference {
  HdrPreviewPreference._();

  static final instance = HdrPreviewPreference._();

  final enabled = ValueNotifier<bool>(true);
  SettingsRepository? _settingsRepository;
  Future<void>? _load;
  bool _hasExplicitPreference = false;

  void configure(SettingsRepository settingsRepository) {
    if (identical(_settingsRepository, settingsRepository)) return;
    _settingsRepository = settingsRepository;
    _load = null;
    _hasExplicitPreference = false;
  }

  Future<void> load() => _load ??= _loadSavedPreference();

  Future<void> _loadSavedPreference() async {
    if (_hasExplicitPreference) return;
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw StateError('HDR preview settings repository is not configured.');
    }
    final savedValue = await settingsRepository.isHdrPhotoPreviewEnabled();
    if (!_hasExplicitPreference) enabled.value = savedValue;
  }

  Future<void> setEnabled(bool value) async {
    final settingsRepository = _settingsRepository;
    if (settingsRepository == null) {
      throw StateError('HDR preview settings repository is not configured.');
    }
    final previous = enabled.value;
    _hasExplicitPreference = true;
    enabled.value = value;
    try {
      await settingsRepository.setHdrPhotoPreviewEnabled(value);
    } catch (_) {
      enabled.value = previous;
      rethrow;
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _settingsRepository = null;
    _load = null;
    _hasExplicitPreference = false;
    enabled.value = true;
  }

  Future<void> toggle() async {
    await load();
    await setEnabled(!enabled.value);
  }
}

bool isGif(Uint8List bytes) =>
    bytes.length >= 6 &&
    bytes[0] == 0x47 &&
    bytes[1] == 0x49 &&
    bytes[2] == 0x46 &&
    bytes[3] == 0x38 &&
    (bytes[4] == 0x37 || bytes[4] == 0x39) &&
    bytes[5] == 0x61;

String _imageMetadataHeader(Uint8List bytes) {
  if (bytes.length < 12) return '';
  return latin1
      .decode(
        bytes.sublist(0, bytes.length < 65536 ? bytes.length : 65536),
        allowInvalid: true,
      )
      .toLowerCase();
}

bool isHdrImage(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final lowerHeader = _imageMetadataHeader(bytes);
  return lowerHeader.contains('hdrgm') ||
      lowerHeader.contains('gainmap') ||
      lowerHeader.contains('smpte2084') ||
      lowerHeader.contains('arib-std-b67') ||
      _hasHeifBrand(bytes);
}

bool isHdrOrMotionPhoto(Uint8List bytes) {
  if (isHdrImage(bytes)) return true;
  final metadata = _imageMetadataHeader(bytes);
  return metadata.contains('microvideooffset') ||
      metadata.contains('motionphoto');
}

bool isHdrVideo(Uint8List bytes) {
  if (bytes.isEmpty) return false;
  const sampleSize = 2 * 1024 * 1024;
  final head = latin1
      .decode(
        bytes.sublist(0, bytes.length < sampleSize ? bytes.length : sampleSize),
        allowInvalid: true,
      )
      .toLowerCase();
  final tailStart = bytes.length > sampleSize ? bytes.length - sampleSize : 0;
  final tail = tailStart == 0
      ? head
      : latin1
            .decode(bytes.sublist(tailStart), allowInvalid: true)
            .toLowerCase();
  const hdrMarkers = [
    'smpte2084',
    'arib-std-b67',
    'mdcv',
    'clli',
    'hdr10',
    'hvc1',
    'hev1',
    'dvh1',
    'dvhe',
    'av01',
  ];
  return hdrMarkers.any(
    (marker) => head.contains(marker) || tail.contains(marker),
  );
}

bool _hasHeifBrand(Uint8List bytes) {
  if (bytes.length < 12) return false;
  final brand = latin1.decode(bytes.sublist(8, 12), allowInvalid: true);
  return const {
    'heic',
    'heix',
    'hevc',
    'hevx',
    'mif1',
    'msf1',
    'avif',
  }.contains(brand);
}

Uint8List? extractMotionPhotoVideo(Uint8List bytes) {
  if (bytes.length < 16) return null;
  final xmp = latin1.decode(
    bytes.sublist(0, bytes.length < 128 * 1024 ? bytes.length : 128 * 1024),
    allowInvalid: true,
  );

  final legacyOffset = RegExp(
    r'(?:GCamera:)?MicroVideoOffset\s*=\s*["\x27](\d+)["\x27]',
    caseSensitive: false,
  ).firstMatch(xmp);
  int? offsetFromEnd = legacyOffset == null
      ? null
      : int.tryParse(legacyOffset.group(1)!);

  if (offsetFromEnd == null) {
    for (final tag in RegExp(
      r'<(?:\w+:)?Item\b[^>]*>',
      caseSensitive: false,
    ).allMatches(xmp)) {
      final value = tag.group(0)!;
      if (!value.toLowerCase().contains('video/mp4') ||
          !value.toLowerCase().contains('motionphoto')) {
        continue;
      }
      final length = RegExp(
        r'(?:Item:)?Length\s*=\s*["\x27](\d+)["\x27]',
        caseSensitive: false,
      ).firstMatch(value);
      final padding = RegExp(
        r'(?:Item:)?Padding\s*=\s*["\x27](\d+)["\x27]',
        caseSensitive: false,
      ).firstMatch(value);
      final videoLength = int.tryParse(length?.group(1) ?? '');
      final trailingPadding = int.tryParse(padding?.group(1) ?? '') ?? 0;
      if (videoLength != null) {
        offsetFromEnd = videoLength + trailingPadding;
        break;
      }
    }
  }

  if (offsetFromEnd == null ||
      offsetFromEnd <= 0 ||
      offsetFromEnd > bytes.length) {
    return null;
  }
  final start = bytes.length - offsetFromEnd;
  if (start + 8 > bytes.length ||
      latin1.decode(bytes.sublist(start + 4, start + 8), allowInvalid: true) !=
          'ftyp') {
    return null;
  }
  return Uint8List.sublistView(bytes, start);
}
