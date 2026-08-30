import 'dart:math' as math;

import 'models/angle_unit.dart';
import 'models/calculator_error.dart';
import 'models/token.dart';

/// Evaluates a Reverse Polish Notation token stream.
class Evaluator {
  const Evaluator();

  /// Largest factorial input that still fits in a double.
  static const int _maxFactorial = 170;

  double evaluate(List<Token> rpn, AngleUnit angleUnit) {
    if (rpn.isEmpty) throw const CalculatorError.syntax();

    final stack = <double>[];

    for (final token in rpn) {
      switch (token.type) {
        case TokenType.number:
        case TokenType.constant:
          stack.add(token.value ?? (throw const CalculatorError.syntax()));
        case TokenType.unaryMinus:
          stack.add(-_pop(stack));
        case TokenType.postfix:
          stack.add(_applyPostfix(token.text, _pop(stack)));
        case TokenType.function:
          stack.add(_applyFunction(token.text, _pop(stack), angleUnit));
        case TokenType.operator:
          final right = _pop(stack);
          final left = _pop(stack);
          stack.add(_applyOperator(token.text, left, right));
        case TokenType.leftParen:
        case TokenType.rightParen:
          throw const CalculatorError.syntax();
      }
    }

    if (stack.length != 1) throw const CalculatorError.syntax();
    return _guard(stack.single);
  }

  double _pop(List<double> stack) {
    if (stack.isEmpty) throw const CalculatorError.syntax();
    return stack.removeLast();
  }

  double _applyOperator(String symbol, double left, double right) {
    switch (symbol) {
      case '+':
        return left + right;
      case '-':
        return left - right;
      case '×':
        return left * right;
      case '÷':
        if (right == 0) throw const CalculatorError.divideByZero();
        return left / right;
      case 'mod':
        if (right == 0) throw const CalculatorError.divideByZero();
        return left.remainder(right);
      case '^':
        final result = math.pow(left, right);
        if (result is! double || result.isNaN) {
          throw const CalculatorError.domain();
        }
        return result;
      default:
        throw const CalculatorError.syntax();
    }
  }

  double _applyPostfix(String symbol, double operand) {
    switch (symbol) {
      case '%':
        return operand / 100.0;
      case '!':
        return _factorial(operand);
      default:
        throw const CalculatorError.syntax();
    }
  }

  double _applyFunction(String name, double operand, AngleUnit angleUnit) {
    switch (name) {
      case 'sin':
        return _snapTrig(math.sin(angleUnit.toRadians(operand)));
      case 'cos':
        return _snapTrig(math.cos(angleUnit.toRadians(operand)));
      case 'tan':
        final radians = angleUnit.toRadians(operand);
        final cosine = math.cos(radians);
        if (cosine.abs() < 1e-12) throw const CalculatorError.domain();
        return _snapTrig(math.sin(radians) / cosine);
      case 'asin':
        if (operand < -1 || operand > 1) throw const CalculatorError.domain();
        return angleUnit.fromRadians(math.asin(operand));
      case 'acos':
        if (operand < -1 || operand > 1) throw const CalculatorError.domain();
        return angleUnit.fromRadians(math.acos(operand));
      case 'atan':
        return angleUnit.fromRadians(math.atan(operand));
      case 'sinh':
        return (math.exp(operand) - math.exp(-operand)) / 2;
      case 'cosh':
        return (math.exp(operand) + math.exp(-operand)) / 2;
      case 'tanh':
        final positive = math.exp(operand);
        final negative = math.exp(-operand);
        final denominator = positive + negative;
        if (denominator.isInfinite) return operand > 0 ? 1.0 : -1.0;
        return (positive - negative) / denominator;
      case 'ln':
        if (operand <= 0) throw const CalculatorError.domain();
        return math.log(operand);
      case 'log':
        if (operand <= 0) throw const CalculatorError.domain();
        return math.log(operand) / math.ln10;
      case '√':
        if (operand < 0) throw const CalculatorError.domain();
        return math.sqrt(operand);
      case '∛':
        return operand < 0
            ? -math.pow(-operand, 1 / 3).toDouble()
            : math.pow(operand, 1 / 3).toDouble();
      case 'exp':
        return math.exp(operand);
      case 'abs':
        return operand.abs();
      default:
        throw const CalculatorError.syntax();
    }
  }

  double _factorial(double operand) {
    if (operand < 0 || operand != operand.roundToDouble()) {
      throw const CalculatorError.domain('Factorial needs a whole number');
    }
    final n = operand.toInt();
    if (n > _maxFactorial) throw const CalculatorError.overflow();
    var result = 1.0;
    for (var i = 2; i <= n; i++) {
      result *= i;
    }
    return result;
  }

  /// Rounds values such as `sin(180)` = 1.2e-16 down to a clean zero.
  double _snapTrig(double value) => value.abs() < 1e-12 ? 0.0 : value;

  double _guard(double value) {
    if (value.isNaN) throw const CalculatorError.domain();
    if (value.isInfinite) throw const CalculatorError.overflow();
    return value;
  }
}
