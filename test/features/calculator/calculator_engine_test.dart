import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/calculator/domain/calculator_engine.dart';
import 'package:photo_vault/features/calculator/domain/models/angle_unit.dart';
import 'package:photo_vault/features/calculator/domain/models/calculator_error.dart';

void main() {
  const engine = CalculatorEngine();

  String eval(String expression, [AngleUnit unit = AngleUnit.degree]) {
    final result = engine.evaluate(expression, unit);
    expect(result.isSuccess, isTrue, reason: 'failed to evaluate $expression');
    return result.formatted!;
  }

  CalculatorErrorKind errorKind(String expression) {
    final result = engine.evaluate(expression, AngleUnit.degree);
    expect(result.isSuccess, isFalse, reason: '$expression should fail');
    return result.error!.kind;
  }

  group('arithmetic and precedence', () {
    test('applies multiplication before addition', () {
      expect(eval('2+3×4'), '14');
    });

    test('respects parentheses', () {
      expect(eval('(2+3)×4'), '20');
    });

    test('auto-balances unclosed parentheses', () {
      expect(eval('2×(3+4'), '14');
    });

    test('subtraction is left-associative', () {
      expect(eval('10-3-2'), '5');
    });

    test('exponentiation is right-associative', () {
      expect(eval('2^3^2'), '512');
    });

    test('unary minus binds looser than exponentiation', () {
      expect(eval('-2^2'), '-4');
    });

    test('unary minus binds tighter than multiplication', () {
      expect(eval('-2×3'), '-6');
    });

    test('supports negation after an operator', () {
      expect(eval('5×-2'), '-10');
    });

    test('mod returns the remainder', () {
      expect(eval('10mod3'), '1');
    });

    test('percent divides by one hundred', () {
      expect(eval('50%'), '0.5');
      expect(eval('200×10%'), '20');
    });
  });

  group('implicit multiplication', () {
    test('number before parenthesis', () {
      expect(eval('2(3+4)'), '14');
    });

    test('parenthesis before parenthesis', () {
      expect(eval('(1+2)(3+4)'), '21');
    });

    test('number before function', () {
      expect(eval('2√(9)'), '6');
    });
  });

  group('scientific functions', () {
    test('trig honours degrees', () {
      expect(eval('sin(30)'), '0.5');
      expect(eval('cos(180)'), '-1');
    });

    test('trig honours radians', () {
      expect(eval('sin(0)', AngleUnit.radian), '0');
      expect(eval('cos(π)', AngleUnit.radian), '-1');
    });

    test('inverse trig returns the active angle unit', () {
      expect(eval('asin(1)'), '90');
      expect(eval('atan(1)'), '45');
    });

    test('logarithms', () {
      expect(eval('log(1000)'), '3');
      expect(eval('ln(e)'), '1');
    });

    test('roots', () {
      expect(eval('√(16)'), '4');
      expect(eval('∛(-27)'), '-3');
    });

    test('factorial', () {
      expect(eval('5!'), '120');
      expect(eval('0!'), '1');
    });

    test('exponent notation', () {
      expect(eval('1.5E3'), '1,500');
      expect(eval('2E-3'), '0.002');
    });
  });

  group('errors', () {
    test('division by zero', () {
      expect(errorKind('5÷0'), CalculatorErrorKind.divideByZero);
      expect(errorKind('5mod0'), CalculatorErrorKind.divideByZero);
    });

    test('domain errors', () {
      expect(errorKind('√(-4)'), CalculatorErrorKind.domain);
      expect(errorKind('log(0)'), CalculatorErrorKind.domain);
      expect(errorKind('(-2)!'), CalculatorErrorKind.domain);
      expect(errorKind('tan(90)'), CalculatorErrorKind.domain);
    });

    test('overflow', () {
      expect(errorKind('500!'), CalculatorErrorKind.overflow);
    });

    test('syntax errors', () {
      expect(errorKind('2+'), CalculatorErrorKind.syntax);
      expect(errorKind(''), CalculatorErrorKind.syntax);
      expect(errorKind('×5'), CalculatorErrorKind.syntax);
    });
  });
}
