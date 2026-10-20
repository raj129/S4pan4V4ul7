import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Removes only the legacy chat directories that contained plaintext copies.
class ChatPrivacyMaintenance {
  static Future<void>? _pending;

  static Future<void> ensureClean() {
    if (!Platform.isAndroid) return Future<void>.value();
    return _pending ??= _clean().onError((Object error, StackTrace stack) {
      _pending = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  static Future<void> _clean() async {
    final temp = await getTemporaryDirectory();
    for (final name in const ['chat_open', 'chat_video', 'chat_to_vault']) {
      final directory = Directory(p.join(temp.path, name));
      if (await directory.exists()) await directory.delete(recursive: true);
    }
  }
}
