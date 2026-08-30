import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/calculator/domain/number_formatter.dart';

void main() {
  const formatter = NumberFormatter();

  test('formats integers with thousands grouping', () {
    expect(formatter.format(1234567), '1,234,567');
    expect(formatter.format(-1234.5), '-1,234.5');
    expect(formatter.format(42), '42');
  });

  test('drops trailing zeros', () {
    expect(formatter.format(2.500), '2.5');
    expect(formatter.format(3.0), '3');
  });

  test('normalises negative zero', () {
    expect(formatter.format(-0.0), '0');
  });

  test('limits significant digits', () {
    expect(formatter.format(1 / 3), '0.333333333333');
  });

  test('switches to scientific notation at the extremes', () {
    expect(formatter.format(1e20), '1E20');
    expect(formatter.format(1.2e-12), '1.2E-12');
  });

  test('formatRaw omits grouping so results can be re-entered', () {
    expect(formatter.formatRaw(1234567), '1234567');
  });
}
