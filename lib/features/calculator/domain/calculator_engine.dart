import 'evaluator.dart';
import 'lexer.dart';
import 'models/angle_unit.dart';
import 'models/calculator_error.dart';
import 'models/eval_result.dart';
import 'number_formatter.dart';
import 'parser.dart';

/// Facade over the lexer → parser → evaluator → formatter pipeline.
///
/// Pure Dart with no Flutter dependency, so it is directly unit testable.
class CalculatorEngine {
  const CalculatorEngine({
    this.lexer = const Lexer(),
    this.parser = const Parser(),
    this.evaluator = const Evaluator(),
    this.formatter = const NumberFormatter(),
  });

  final Lexer lexer;
  final Parser parser;
  final Evaluator evaluator;
  final NumberFormatter formatter;

  /// Evaluates [expression]; never throws.
  EvalResult evaluate(String expression, AngleUnit angleUnit) {
    if (expression.trim().isEmpty) {
      return const EvalResult.failure(CalculatorError.syntax('Empty'));
    }
    try {
      final tokens = lexer.tokenize(expression);
      final rpn = parser.toRpn(tokens);
      final value = evaluator.evaluate(rpn, angleUnit);
      return EvalResult.success(value, formatter.format(value));
    } on CalculatorError catch (error) {
      return EvalResult.failure(error);
    } catch (_) {
      return const EvalResult.failure(CalculatorError.syntax());
    }
  }
}
