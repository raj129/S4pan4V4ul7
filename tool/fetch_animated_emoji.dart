// Downloads every Noto Animated Emoji (Lottie) into assets/animated_emoji/.
//
// Run from the project root:  dart run tool/fetch_animated_emoji.dart
//
// Source: https://googlefonts.github.io/noto-emoji-animation/
// License: CC BY 4.0 (see assets/animated_emoji/LICENSE).
import 'dart:convert';
import 'dart:io';

const _indexUrl =
    'https://googlefonts.github.io/noto-emoji-animation/data/api.json';
String _lottieUrl(String codepoint) =>
    'https://fonts.gstatic.com/s/e/notoemoji/latest/$codepoint/lottie.json';

const _concurrency = 12;

Future<void> main() async {
  final outDir = Directory('assets/animated_emoji');
  await outDir.create(recursive: true);
  final client = HttpClient();

  try {
    final index = jsonDecode(await _get(client, _indexUrl)) as Map;
    final codepoints = [
      for (final icon in index['icons'] as List)
        (icon as Map)['codepoint'] as String,
    ];

    final done = <String>[];
    final failed = <String>[];
    var next = 0;

    Future<void> worker() async {
      while (next < codepoints.length) {
        final cp = codepoints[next++];
        final file = File('${outDir.path}/$cp.json');
        try {
          if (!await file.exists()) {
            final body = await _get(client, _lottieUrl(cp));
            // Re-encode to strip any whitespace; also validates the JSON.
            await file.writeAsString(jsonEncode(jsonDecode(body)));
          }
          done.add(cp);
        } on _NotFound {
          // Google publishes no animation for a few emoji (e.g. © and ®);
          // those simply render as static text.
          stdout.writeln('no animation for $cp, skipped');
        } catch (e) {
          failed.add(cp);
          stderr.writeln('failed $cp: $e');
        }
      }
    }

    await Future.wait(List.generate(_concurrency, (_) => worker()));

    done.sort();
    await File('${outDir.path}/index.json').writeAsString(jsonEncode(done));

    var bytes = 0;
    await for (final f in outDir.list()) {
      if (f is File) bytes += await f.length();
    }
    stdout.writeln(
      'Downloaded ${done.length}/${codepoints.length} animations '
      '(${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB), '
      '${failed.length} failed.',
    );
    if (failed.isNotEmpty) exitCode = 1;
  } finally {
    client.close();
  }
}

Future<String> _get(HttpClient client, String url) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode == 404) {
        await res.drain<void>();
        throw const _NotFound();
      }
      if (res.statusCode != 200) {
        await res.drain<void>();
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
      }
      return await res.transform(utf8.decoder).join();
    } on _NotFound {
      rethrow;
    } catch (_) {
      if (attempt >= 3) rethrow;
      await Future<void>.delayed(Duration(seconds: attempt));
    }
  }
}

class _NotFound implements Exception {
  const _NotFound();
}
