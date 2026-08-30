/// Kinds of lexical units produced by the [Lexer].
enum TokenType {
  /// A literal number, possibly with a decimal part and an `E` exponent.
  number,

  /// A named constant such as `π` or `e`.
  constant,

  /// A binary infix operator such as `+`, `×` or `^`.
  operator,

  /// A prefix negation, emitted by the lexer for a leading/contextual `-`.
  unaryMinus,

  /// A suffix operator such as `!` (factorial) or `%` (per-cent).
  postfix,

  /// A named prefix function such as `sin` or `ln`.
  function,

  leftParen,
  rightParen,
}

/// A single lexical unit of a calculator expression.
class Token {
  const Token(this.type, this.text, [this.value]);

  const Token.number(this.value, this.text) : type = TokenType.number;

  final TokenType type;

  /// The source text of the token, used for error messages and debugging.
  final String text;

  /// Numeric payload for [TokenType.number] and [TokenType.constant].
  final double? value;

  bool get isOperand =>
      type == TokenType.number || type == TokenType.constant;

  @override
  String toString() => '${type.name}:$text';

  @override
  bool operator ==(Object other) =>
      other is Token &&
      other.type == type &&
      other.text == text &&
      other.value == value;

  @override
  int get hashCode => Object.hash(type, text, value);
}

/// Operator metadata used by the shunting-yard [Parser].
class OperatorSpec {
  const OperatorSpec(this.precedence, {this.rightAssociative = false});

  final int precedence;
  final bool rightAssociative;
}

/// Precedence table. Higher binds tighter.
const Map<String, OperatorSpec> kOperators = <String, OperatorSpec>{
  '+': OperatorSpec(2),
  '-': OperatorSpec(2),
  '×': OperatorSpec(4),
  '÷': OperatorSpec(4),
  'mod': OperatorSpec(4),
  '^': OperatorSpec(8, rightAssociative: true),
};

/// Precedence of prefix negation: tighter than `×`/`÷`, looser than `^`
/// so that `-2^2` evaluates to `-4`.
const int kUnaryMinusPrecedence = 6;

/// Names recognised as prefix functions.
const Set<String> kFunctions = <String>{
  'sin',
  'cos',
  'tan',
  'asin',
  'acos',
  'atan',
  'sinh',
  'cosh',
  'tanh',
  'ln',
  'log',
  '√',
  '∛',
  'exp',
  'abs',
};

/// Named constants and their values.
const Map<String, double> kConstants = <String, double>{
  'π': 3.141592653589793,
  'e': 2.718281828459045,
};
