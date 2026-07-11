import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/application/services/pin_validator.dart';

void main() {
  group('PinValidator', () {
    final validator = PinValidator();

    group('validate()', () {
      test('accepts a valid 6-digit PIN', () {
        expect(validator.validate('482930'), isNull);
      });

      test('rejects PIN shorter than 6 digits', () {
        expect(validator.validate('1234'), isNotNull);
      });

      test('rejects PIN longer than 6 digits', () {
        expect(validator.validate('1234567'), isNotNull);
      });

      test('rejects non-numeric characters', () {
        expect(validator.validate('12345a'), isNotNull);
      });

      test('rejects 000000', () {
        expect(validator.validate('000000'), isNotNull);
      });

      test('rejects 123456', () {
        expect(validator.validate('123456'), isNotNull);
      });

      test('rejects 654321', () {
        expect(validator.validate('654321'), isNotNull);
      });

      test('rejects 111111', () {
        expect(validator.validate('111111'), isNotNull);
      });

      test('accepts a unique non-weak PIN', () {
        expect(validator.validate('847291'), isNull);
      });
    });

    group('matches()', () {
      test('returns true when PINs are identical', () {
        expect(validator.matches('482930', '482930'), isTrue);
      });

      test('returns false when PINs differ', () {
        expect(validator.matches('482930', '482931'), isFalse);
      });

      test('returns false when confirm is empty', () {
        expect(validator.matches('482930', ''), isFalse);
      });
    });
  });
}
