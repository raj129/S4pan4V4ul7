import 'package:flutter_test/flutter_test.dart';

import 'package:photo_vault/application/services/pin_validator.dart';

void main() {
  group('PinValidator', () {
    final validator = PinValidator();

    group('validate()', () {
      test('accepts a valid 4-digit PIN', () {
        expect(validator.validate('4829'), isNull);
      });

      test('rejects PIN shorter than 4 digits', () {
        expect(validator.validate('123'), isNotNull);
      });

      test('rejects PIN longer than 4 digits', () {
        expect(validator.validate('12345'), isNotNull);
      });

      test('rejects non-numeric characters', () {
        expect(validator.validate('123a'), isNotNull);
      });

      test('rejects 0000', () {
        expect(validator.validate('0000'), isNotNull);
      });

      test('rejects 1234', () {
        expect(validator.validate('1234'), isNotNull);
      });

      test('rejects 4321', () {
        expect(validator.validate('4321'), isNotNull);
      });

      test('rejects 1111', () {
        expect(validator.validate('1111'), isNotNull);
      });

      test('accepts a unique non-weak PIN', () {
        expect(validator.validate('8472'), isNull);
      });
    });

    group('matches()', () {
      test('returns true when PINs are identical', () {
        expect(validator.matches('4829', '4829'), isTrue);
      });

      test('returns false when PINs differ', () {
        expect(validator.matches('4829', '4830'), isFalse);
      });

      test('returns false when confirm is empty', () {
        expect(validator.matches('4829', ''), isFalse);
      });
    });
  });
}
