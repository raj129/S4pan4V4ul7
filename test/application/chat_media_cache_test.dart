import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/application/services/chat_media_cache.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chat_media_cache_test');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  ChatMediaCache cacheWith({int maxBytes = 1024 * 1024}) =>
      ChatMediaCache(directory: dir, maxBytes: maxBytes);

  test('stores and returns the bytes it was given', () async {
    final cache = cacheWith();
    final bytes = Uint8List.fromList([1, 2, 3, 4]);

    await cache.write('chat_media/t/m/a.jpg.enc', bytes);

    expect(await cache.read('chat_media/t/m/a.jpg.enc'), bytes);
  });

  test('an unknown path is a miss, not an error', () async {
    expect(await cacheWith().read('chat_media/t/m/missing.enc'), isNull);
  });

  test('a storage path with slashes maps to one flat file', () async {
    final cache = cacheWith();

    await cache.write('chat_media/a/b/c.enc', Uint8List.fromList([9]));

    final files = dir.listSync().whereType<File>().toList();
    expect(files, hasLength(1));
    final name = files.single.uri.pathSegments.last;
    expect(name, matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('evicts the oldest entries once the cap is passed', () async {
    final cache = cacheWith(maxBytes: 300);

    await cache.write('old', Uint8List(200));
    // Distinct timestamps, so "least recently used" is unambiguous.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await cache.write('new', Uint8List(200));

    expect(await cache.read('old'), isNull);
    expect(await cache.read('new'), isNotNull);
  });

  test('clear removes everything', () async {
    final cache = cacheWith();
    await cache.write('a', Uint8List.fromList([1]));

    await cache.clear();

    expect(await cache.read('a'), isNull);
  });
}
