import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/domain/search/chat_search_tokenizer.dart';

void main() {
  final key = Uint8List.fromList(List.filled(32, 1));

  group('matching', () {
    test('matches word prefixes, case- and accent-insensitively', () {
      expect(ChatSearchTokenizer.matches('Meet at the Café', 'cafe'), isTrue);
      expect(ChatSearchTokenizer.matches('Meet at the Café', 'MEE'), isTrue);
      expect(ChatSearchTokenizer.matches('Meet at the Café', 'eet'), isFalse);
    });

    test('requires every query word', () {
      const text = 'dinner on friday at noon';
      expect(ChatSearchTokenizer.matches(text, 'fri din'), isTrue);
      expect(ChatSearchTokenizer.matches(text, 'friday lunch'), isFalse);
    });

    test('ignores punctuation-only queries', () {
      expect(ChatSearchTokenizer.queryTerms('  ?!  '), isEmpty);
      expect(ChatSearchTokenizer.matches('anything', '?!'), isFalse);
    });

    test('long words match beyond the indexed prefix length', () {
      const word = 'supercalifragilisticexpialidocious';
      expect(ChatSearchTokenizer.matches(word, word), isTrue);
    });

    test('unspaced scripts match inside a run', () {
      expect(ChatSearchTokenizer.matches('明日東京へ行く', '東京'), isTrue);
      expect(ChatSearchTokenizer.matches('明日東京へ行く', '大阪'), isFalse);
    });
  });

  group('hashing', () {
    test('stores keyed hashes, never the words', () {
      final hashes = ChatSearchTokenizer.hashedIndexTerms(key, 'secret plan');
      expect(hashes, isNotEmpty);
      expect(hashes.any((h) => h.contains('secret')), isFalse);
    });

    test('query hashes are a subset of the matching message hashes', () {
      final indexed = ChatSearchTokenizer.hashedIndexTerms(key, 'Secret plan');
      final query = ChatSearchTokenizer.hashedQueryTerms(key, 'sec pl');
      expect(indexed.toSet().containsAll(query), isTrue);
    });

    test('different thread keys produce unrelated hashes', () {
      final other = Uint8List.fromList(List.filled(32, 2));
      expect(
        ChatSearchTokenizer.hashTerm(key, 'plan'),
        isNot(ChatSearchTokenizer.hashTerm(other, 'plan')),
      );
    });
  });

  group('highlightRanges', () {
    test('highlights the matched start of each word', () {
      const text = 'Planning the plan';
      final ranges = ChatSearchTokenizer.highlightRanges(text, 'plan');
      expect(ranges.map((r) => text.substring(r.$1, r.$2)).toList(), [
        'Plan',
        'plan',
      ]);
    });

    test('maps accent-folded matches back onto the original text', () {
      const text = 'Café time';
      final ranges = ChatSearchTokenizer.highlightRanges(text, 'cafe');
      expect(ranges.map((r) => text.substring(r.$1, r.$2)), ['Café']);
    });

    test('no query means no highlight', () {
      expect(ChatSearchTokenizer.highlightRanges('hello', ''), isEmpty);
    });
  });
}
