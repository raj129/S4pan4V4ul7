import 'calculator_error.dart';

/// Outcome of evaluating an expression: either a numeric value or an error.
class EvalResult {
  const EvalResult.success(this.value, this.formatted) : error = null;

  const EvalResult.failure(CalculatorError this.error)
    : value = null,
      formatted = null;

  final double? value;

  /// Display-ready rendering of [value].
  final String? formatted;

  final CalculatorError? error;

  bool get isSuccess => error == null;
}
