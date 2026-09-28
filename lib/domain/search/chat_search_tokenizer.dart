import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Turns message text into search terms for the local keyed search index.
///
/// The index never stores words: each term is replaced by a truncated
/// HMAC-SHA256 under a per-thread search key (see [hashTerm]), so the table
/// is unreadable without that key yet still answers "which messages contain
/// a word starting with …" as a single indexed lookup.
///
/// Matching is WhatsApp/Signal style — by word start, case- and
/// accent-insensitive. Scripts written without spaces (Han, Kana, Thai) are
/// indexed as single characters and character bigrams instead.
class ChatSearchTokenizer {
  const ChatSearchTokenizer._();

  /// Shortest prefix indexed for a multi-character word.
  static const minPrefix = 2;

  /// Longest prefix indexed; longer query words are truncated to this, which
  /// can only widen (never narrow) the candidate set.
  static const maxPrefix = 16;

  /// Bytes of the HMAC kept per term. 128 bits makes accidental collisions
  /// irrelevant while halving index size.
  static const _hashBytes = 16;

  static final _word = RegExp(r'[\p{L}\p{N}\p{M}]+', unicode: true);
  static final _mark = RegExp(r'^\p{M}$', unicode: true);
  static final _unspaced = RegExp(
    r'[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}]',
    unicode: true,
  );

  /// Every term a message with [text] should be findable by.
  static Set<String> indexTerms(String text) {
    final terms = <String>{};
    for (final word in _words(text)) {
      for (final segment in _segments(word.normalized)) {
        terms.addAll(
          segment.unspaced ? _ngrams(segment.text) : _prefixes(segment.text),
        );
      }
    }
    return terms;
  }

  /// Terms a message must contain *all* of to match [query].
  static Set<String> queryTerms(String query) {
    final terms = <String>{};
    for (final word in _words(query)) {
      for (final segment in _segments(word.normalized)) {
        final runes = segment.text.runes.toList();
        if (!segment.unspaced) {
          terms.add(String.fromCharCodes(runes.take(maxPrefix)));
        } else if (runes.length == 1) {
          terms.add(segment.text);
        } else {
          for (var i = 0; i + 1 < runes.length; i++) {
            terms.add(String.fromCharCodes(runes.sublist(i, i + 2)));
          }
        }
      }
    }
    return terms;
  }

  /// Keyed, truncated hash of [term] as stored in the index.
  static String hashTerm(Uint8List key, String term) {
    final digest = Hmac(sha256, key).convert(utf8.encode(term)).bytes;
    return base64Url.encode(digest.sublist(0, _hashBytes));
  }

  /// [indexTerms] of [text], hashed under [key].
  static List<String> hashedIndexTerms(Uint8List key, String text) => [
    for (final t in indexTerms(text)) hashTerm(key, t),
  ];

  /// [queryTerms] of [query], hashed under [key].
  static List<String> hashedQueryTerms(Uint8List key, String query) => [
    for (final t in queryTerms(query)) hashTerm(key, t),
  ];

  /// Whether [text] matches [query] under the same rules as the index.
  static bool matches(String text, String query) {
    final wanted = queryTerms(query);
    if (wanted.isEmpty) return false;
    final have = indexTerms(text);
    return wanted.every(have.contains);
  }

  /// Character ranges of [text] to highlight for [query]: the matched start of
  /// every word beginning with a query word, and every unspaced-script
  /// occurrence. Ranges are sorted and non-overlapping.
  static List<(int, int)> highlightRanges(String text, String query) {
    final querySegments = [
      for (final w in _words(query)) ..._segments(w.normalized),
    ];
    if (querySegments.isEmpty) return const [];
    final ranges = <(int, int)>[];

    for (final word in _words(text)) {
      var best = 0;
      for (final q in querySegments) {
        if (q.unspaced) continue;
        final int matched;
        if (word.normalized.startsWith(q.text)) {
          matched = q.text.length;
        } else {
          final prefix = String.fromCharCodes(q.text.runes.take(maxPrefix));
          if (!word.normalized.startsWith(prefix)) continue;
          matched = prefix.length;
        }
        if (matched > best) best = matched;
      }
      if (best > 0) ranges.add((word.start, word.originalEndFor(best)));
    }

    final lower = text.toLowerCase();
    for (final q in querySegments) {
      if (!q.unspaced) continue;
      var from = 0;
      while (true) {
        final i = lower.indexOf(q.text, from);
        if (i < 0) break;
        ranges.add((i, i + q.text.length));
        from = i + q.text.length;
      }
    }

    ranges.sort((a, b) => a.$1.compareTo(b.$1));
    final merged = <(int, int)>[];
    for (final r in ranges) {
      if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
      } else {
        merged.add(r);
      }
    }
    return merged;
  }

  // ---------------------------------------------------------------------------

  static Iterable<_Word> _words(String text) sync* {
    for (final m in _word.allMatches(text)) {
      final normalized = StringBuffer();
      final offsets = <int>[];
      var cursor = m.start;
      for (final rune in m.group(0)!.runes) {
        final original = String.fromCharCode(rune);
        final folded = _fold(original);
        for (var i = 0; i < folded.length; i++) {
          offsets.add(cursor);
        }
        normalized.write(folded);
        cursor += original.length;
      }
      final value = normalized.toString();
      if (value.isEmpty) continue;
      yield _Word(m.start, m.end, value, offsets);
    }
  }

  static Iterable<_Segment> _segments(String word) sync* {
    final buf = StringBuffer();
    bool? unspaced;
    for (final rune in word.runes) {
      final ch = String.fromCharCode(rune);
      final isUnspaced = _unspaced.hasMatch(ch);
      if (unspaced != null && isUnspaced != unspaced) {
        yield _Segment(buf.toString(), unspaced);
        buf.clear();
      }
      unspaced = isUnspaced;
      buf.write(ch);
    }
    if (buf.isNotEmpty) yield _Segment(buf.toString(), unspaced!);
  }

  static Iterable<String> _prefixes(String word) sync* {
    final runes = word.runes.toList();
    if (runes.length < minPrefix) {
      yield word;
      return;
    }
    final upTo = runes.length < maxPrefix ? runes.length : maxPrefix;
    for (var n = minPrefix; n <= upTo; n++) {
      yield String.fromCharCodes(runes.sublist(0, n));
    }
  }

  static Iterable<String> _ngrams(String run) sync* {
    final runes = run.runes.toList();
    for (var i = 0; i < runes.length; i++) {
      yield String.fromCharCode(runes[i]);
      if (i + 1 < runes.length) {
        yield String.fromCharCodes(runes.sublist(i, i + 2));
      }
    }
  }

  /// Lowercase and strip accents from a single character.
  static String _fold(String ch) {
    if (_mark.hasMatch(ch)) return '';
    final lower = ch.toLowerCase();
    return _accentFold[lower] ?? lower;
  }

  static const _accentFold = <String, String>{
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', //
    'ă': 'a', 'ą': 'a', 'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd', //
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ė': 'e', 'ę': 'e', //
    'ě': 'e', 'ğ': 'g', 'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', //
    'į': 'i', 'ı': 'i', 'ł': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n', 'ò': 'o', //
    'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ő': 'o', //
    'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ș': 's', 'ť': 't', 'ţ': 't', //
    'ț': 't', 'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', //
    'ű': 'u', 'ų': 'u', 'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z', //
    'ß': 'ss', 'æ': 'ae', 'œ': 'oe', //
  };
}

class _Word {
  const _Word(this.start, this.end, this.normalized, this._offsets);

  /// Offsets into the original text.
  final int start;
  final int end;
  final String normalized;

  /// Original-text offset for each code unit of [normalized].
  final List<int> _offsets;

  /// Original-text end offset covering the first [length] normalized units.
  ///
  /// A folded character can expand (ß → ss); the end never splits one.
  int originalEndFor(int length) {
    var n = length;
    while (n < _offsets.length && _offsets[n] == _offsets[n - 1]) {
      n++;
    }
    return n >= _offsets.length ? end : _offsets[n];
  }
}

class _Segment {
  const _Segment(this.text, this.unspaced);
  final String text;
  final bool unspaced;
}
