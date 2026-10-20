import 'package:flutter/foundation.dart';

/// Debug measurements contain no paths, account IDs, keys or media content.
class ChatMediaTimings {
  static void record(
    String stage,
    Stopwatch watch, {
    int? bytes,
    bool? cacheHit,
  }) {
    if (kReleaseMode) return;
    debugPrint(
      'ChatMediaTiming stage=$stage elapsedMs=${watch.elapsedMilliseconds}'
      '${bytes == null ? '' : ' bytes=$bytes'}'
      '${cacheHit == null ? '' : ' cacheHit=$cacheHit'}',
    );
  }
}
