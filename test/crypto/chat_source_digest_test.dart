import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/chat/application/media/chat_source_digest.dart';

void main() {
  test(
    'large-source fingerprint uses owned worker bytes without changing input',
        () async {
      final input = Uint8List.fromList(
        List.generate(1024 * 1024, (i) => i % 251),
      ).asUnmodifiableView();
      final expected = sha256.convert(input).toString();
      expect(await chatSourceDigest(input), expected);
      expect(input[250], 250);
      expect(input[251], 0);
    },
  );
}
