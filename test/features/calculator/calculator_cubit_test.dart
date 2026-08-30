import 'package:flutter_test/flutter_test.dart';
import 'package:photo_vault/features/calculator/application/calculator_cubit.dart';
import 'package:photo_vault/features/calculator/domain/models/angle_unit.dart';

void main() {
  late CalculatorCubit cubit;

  setUp(() => cubit = CalculatorCubit());
  tearDown(() => cubit.close());

  void type(String keys) {
    for (final key in keys.split('')) {
      cubit.input(key);
    }
  }

  group('editing rules', () {
    test('replaces a trailing operator', () {
      type('5×');
      cubit.input('+');
      expect(cubit.state.expression, '5+');
    });

    test('keeps a minus after another operator as negation', () {
      type('5×');
      cubit.input('-');
      expect(cubit.state.expression, '5×-');
    });

    test('allows only one decimal point per number', () {
      type('1.2');
      cubit.input('.');
      expect(cubit.state.expression, '1.2');
    });

    test('prefixes a bare decimal point with zero', () {
      cubit.input('.');
      expect(cubit.state.expression, '0.');
    });

    test('ignores a leading operator other than minus', () {
      cubit.input('×');
      expect(cubit.state.expression, '');
      cubit.input('-');
      expect(cubit.state.expression, '-');
    });

    test('backspace removes a whole function name', () {
      cubit.input('sin(');
      cubit.backspace();
      expect(cubit.state.expression, '');
    });

    test('smart parenthesis opens then closes', () {
      cubit.inputSmartParen();
      expect(cubit.state.expression, '(');
      type('2+3');
      cubit.inputSmartParen();
      expect(cubit.state.expression, '(2+3)');
    });

    test('AC resets the expression and preview', () {
      type('2+3');
      cubit.clearAll();
      expect(cubit.state.expression, '');
      expect(cubit.state.preview, '');
    });
  });

  group('live preview', () {
    test('appears once the expression is evaluable', () {
      type('2+3');
      expect(cubit.state.preview, '5');
    });

    test('is hidden for a bare number', () {
      type('42');
      expect(cubit.state.preview, '');
    });

    test('is hidden for incomplete input rather than erroring', () {
      type('2+');
      expect(cubit.state.preview, '');
      expect(cubit.state.hasError, isFalse);
    });
  });

  group('equals', () {
    test('commits the result and records history', () {
      type('2+3×4');
      cubit.equals();
      expect(cubit.state.expression, '14');
      expect(cubit.state.justEvaluated, isTrue);
      expect(cubit.state.history.single.expression, '2+3×4');
      expect(cubit.state.history.single.result, '14');
    });

    test('a digit after equals starts a new expression', () {
      type('2+3');
      cubit.equals();
      cubit.input('7');
      expect(cubit.state.expression, '7');
    });

    test('an operator after equals continues from the result', () {
      type('2+3');
      cubit.equals();
      cubit.input('×');
      expect(cubit.state.expression, '5×');
    });

    test('surfaces an error message on invalid input', () {
      type('5÷0');
      cubit.equals();
      expect(cubit.state.hasError, isTrue);
      expect(cubit.state.errorMessage, "Can't divide by zero");
    });

    test('the next keystroke clears the error', () {
      type('5÷0');
      cubit.equals();
      cubit.backspace();
      expect(cubit.state.hasError, isFalse);
    });
  });

  group('toggles', () {
    test('angle unit flips and recomputes the preview', () {
      cubit.input('sin(');
      type('30');
      cubit.input(')');
      expect(cubit.state.preview, '0.5');
      cubit.toggleAngleUnit();
      expect(cubit.state.angleUnit, AngleUnit.radian);
      expect(cubit.state.preview, isNot('0.5'));
    });

    test('scientific and inverse toggles', () {
      expect(cubit.state.scientificExpanded, isFalse);
      cubit.toggleScientific();
      expect(cubit.state.scientificExpanded, isTrue);
      cubit.toggleInverse();
      expect(cubit.state.inverseMode, isTrue);
    });
  });

  group('memory', () {
    test('M+ accumulates and MR recalls', () {
      type('12');
      cubit.memoryAdd();
      expect(cubit.state.memoryActive, isTrue);
      cubit.clearAll();
      cubit.memoryRecall();
      expect(cubit.state.expression, '12');
    });

    test('M- subtracts and MC clears', () {
      type('12');
      cubit.memoryAdd();
      cubit.clearAll();
      type('5');
      cubit.memorySubtract();
      cubit.clearAll();
      cubit.memoryRecall();
      expect(cubit.state.expression, '7');
      cubit.memoryClear();
      expect(cubit.state.memoryActive, isFalse);
    });

    test('MR does nothing when memory is empty', () {
      cubit.memoryRecall();
      expect(cubit.state.expression, '');
    });
  });

  group('history', () {
    test('newest entry comes first and can be reused', () {
      type('1+1');
      cubit.equals();
      cubit.clearAll();
      type('2+2');
      cubit.equals();

      expect(cubit.state.history.first.result, '4');
      cubit.applyHistoryResult(cubit.state.history.last);
      expect(cubit.state.expression, '2');
    });

    test('clear empties the list', () {
      type('1+1');
      cubit.equals();
      cubit.clearHistory();
      expect(cubit.state.history, isEmpty);
    });
  });
}
