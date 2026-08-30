import 'models/calculator_error.dart';
import 'models/token.dart';

/// Turns a raw expression string into a list of [Token]s.
///
/// Handles decimal numbers with optional `E` exponents, multi-character
/// function names, constants, prefix negation and implicit multiplication
/// (`2(3+4)`, `2π`, `(1+2)(3+4)`, `2sin(1)`).
class Lexer {
  const Lexer();

  static const Set<String> _digits = <String>{
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
  };

  /// Function and constant names, longest first so `asin` wins over `a`.
  static final List<String> _names = <String>[
    ...kFunctions,
    ...kConstants.keys,
    'mod',
  ]..sort((a, b) => b.length.compareTo(a.length));

  List<Token> tokenize(String input) {
    final tokens = <Token>[];
    var i = 0;

    while (i < input.length) {
      final char = input[i];

      if (char == ' ') {
        i++;
        continue;
      }

      if (_digits.contains(char) || char == '.') {
        final start = i;
        var seenDot = false;
        while (i < input.length) {
          final c = input[i];
          if (_digits.contains(c)) {
            i++;
          } else if (c == '.' && !seenDot) {
            seenDot = true;
            i++;
          } else if (c == 'E' && i + 1 < input.length) {
            // Exponent marker: consume `E`, an optional sign, then digits.
            final next = input[i + 1];
            final hasDigits =
                _digits.contains(next) ||
                ((next == '-' || next == '+') &&
                    i + 2 < input.length &&
                    _digits.contains(input[i + 2]));
            if (!hasDigits) break;
            i += 2;
            while (i < input.length && _digits.contains(input[i])) {
              i++;
            }
            break;
          } else {
            break;
          }
        }
        final text = input.substring(start, i);
        final value = double.tryParse(text);
        if (value == null) throw const CalculatorError.syntax();
        _insertImplicitMultiplication(tokens);
        tokens.add(Token.number(value, text));
        continue;
      }

      final name = _matchName(input, i);
      if (name != null) {
        i += name.length;
        if (kConstants.containsKey(name)) {
          _insertImplicitMultiplication(tokens);
          tokens.add(Token(TokenType.constant, name, kConstants[name]));
        } else if (name == 'mod') {
          tokens.add(const Token(TokenType.operator, 'mod'));
        } else {
          _insertImplicitMultiplication(tokens);
          tokens.add(Token(TokenType.function, name));
        }
        continue;
      }

      if (char == '(') {
        _insertImplicitMultiplication(tokens);
        tokens.add(const Token(TokenType.leftParen, '('));
        i++;
        continue;
      }

      if (char == ')') {
        tokens.add(const Token(TokenType.rightParen, ')'));
        i++;
        continue;
      }

      if (char == '!' || char == '%') {
        tokens.add(Token(TokenType.postfix, char));
        i++;
        continue;
      }

      if (char == '-' || char == '\u2212') {
        tokens.add(
          _expectsOperand(tokens)
              ? const Token(TokenType.unaryMinus, '-')
              : const Token(TokenType.operator, '-'),
        );
        i++;
        continue;
      }

      if (kOperators.containsKey(char)) {
        tokens.add(Token(TokenType.operator, char));
        i++;
        continue;
      }

      throw CalculatorError.syntax('Unexpected "$char"');
    }

    return tokens;
  }

  String? _matchName(String input, int index) {
    for (final name in _names) {
      if (input.startsWith(name, index)) return name;
    }
    return null;
  }

  /// True when the next token must be an operand (start of input, after an
  /// operator, after `(`).
  bool _expectsOperand(List<Token> tokens) {
    if (tokens.isEmpty) return true;
    final last = tokens.last;
    return last.type == TokenType.operator ||
        last.type == TokenType.unaryMinus ||
        last.type == TokenType.leftParen ||
        last.type == TokenType.function;
  }

  /// Inserts a `×` when an operand directly follows a closing operand,
  /// e.g. `2π`, `2(3)`, `(1+2)3`, `2sin(1)`.
  void _insertImplicitMultiplication(List<Token> tokens) {
    if (tokens.isEmpty) return;
    final last = tokens.last;
    final closesOperand =
        last.isOperand ||
        last.type == TokenType.rightParen ||
        last.type == TokenType.postfix;
    if (closesOperand) {
      tokens.add(const Token(TokenType.operator, '×'));
    }
  }
}
