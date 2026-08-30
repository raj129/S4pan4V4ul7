/// Categories of failures the calculator engine can report.
enum CalculatorErrorKind { syntax, divideByZero, domain, overflow }

/// A recoverable evaluation failure carrying a short, user-facing message.
class CalculatorError implements Exception {
  const CalculatorError(this.kind, this.message);

  const CalculatorError.syntax([this.message = 'Syntax error'])
    : kind = CalculatorErrorKind.syntax;

  const CalculatorError.divideByZero()
    : kind = CalculatorErrorKind.divideByZero,
      message = "Can't divide by zero";

  const CalculatorError.domain([this.message = 'Undefined result'])
    : kind = CalculatorErrorKind.domain;

  const CalculatorError.overflow()
    : kind = CalculatorErrorKind.overflow,
      message = 'Number too large';

  final CalculatorErrorKind kind;
  final String message;

  @override
  String toString() => 'CalculatorError($kind): $message';
}
